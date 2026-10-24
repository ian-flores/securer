#' Create a Unix domain socket server
#'
#' @param path Character string, the file path for the socket
#' @return A server connection object from processx
#' @keywords internal
ipc_create_server <- function(path) {
  processx::conn_create_unix_socket(path)
}

#' Accept a client connection on a Unix domain socket server
#'
#' Polls the server connection and accepts the incoming client.
#' `processx::conn_accept_unix_socket()` doesn't return a new connection. It
#' switches the server connection itself to the "connected_server" state,
#' and from then on the same `server_conn` object carries data both ways.
#'
#' @param server_conn The server connection returned by [ipc_create_server()]
#' @param timeout Timeout in milliseconds (default 5000)
#' @return Invisible NULL; the server_conn is modified in place
#' @keywords internal
ipc_accept <- function(server_conn, timeout = 5000L) {
  poll_result <- processx::poll(list(server_conn), timeout)
  if (poll_result[[1]] != "connect") {
    stop("Timeout waiting for client connection", call. = FALSE)
  }
  processx::conn_accept_unix_socket(server_conn)
  invisible(NULL)
}

# Largest IPC message, in bytes, that either side will send or accept.
# Bigger messages are refused with a clear error instead of being read
# into memory, so a misbehaving child can't exhaust the parent.
ipc_max_message_size <- 1048576L

#' Encode a value for IPC
#'
#' Plain JSON turns a data frame into a list of rows and drops column types,
#' factor levels and classes. This tags data frames (recursively, inside
#' plain lists) so [ipc_decode_value()] can rebuild them exactly. Other
#' values are left for jsonlite to encode as before.
#'
#' @param x A value to send.
#' @return A JSON-ready value.
#' @keywords internal
ipc_encode_value <- function(x) {
  if (is.data.frame(x)) {
    rn <- .row_names_info(x, 0L)
    compact <- is.integer(rn) && length(rn) == 2L && is.na(rn[1L])
    list(
      `__securer__` = "data.frame",
      class = I(intersect(class(x), c("tbl_df", "tbl", "data.frame"))),
      names = I(names(x)),
      row_names = if (compact) {
        list(compact = rn[2L])
      } else {
        ipc_encode_column(attr(x, "row.names"))
      },
      columns = unname(lapply(x, ipc_encode_column))
    )
  } else if (is.list(x) && is.null(oldClass(x))) {
    lapply(x, ipc_encode_value)
  } else {
    x
  }
}

#' Encode one data frame column for IPC
#'
#' @param x An atomic vector or list column.
#' @return A tagged list.
#' @keywords internal
ipc_encode_column <- function(x) {
  if (is.list(x)) {
    return(list(
      `__securer__` = "column",
      type = "list",
      values = unname(lapply(x, ipc_encode_value))
    ))
  }
  type <- typeof(x)
  if (!type %in% c("logical", "integer", "double", "character")) {
    stop("Data frame columns of type '", type,
         "' can't be sent over IPC", call. = FALSE)
  }
  values <- unclass(x)
  attributes(values) <- NULL
  # I() keeps length-1 vectors as JSON arrays under auto_unbox
  out <- list(
    `__securer__` = "column",
    type = type,
    class = if (!is.null(oldClass(x))) I(oldClass(x)),
    levels = if (!is.null(levels(x))) I(levels(x)),
    tzone = attr(x, "tzone", exact = TRUE),
    units = attr(x, "units", exact = TRUE),
    values = I(values)
  )
  out[!vapply(out, is.null, logical(1))]
}

#' Decode a value received over IPC
#'
#' Reverses [ipc_encode_value()]. Only data frames and a fixed set of column
#' classes are rebuilt, so data from the child can't attach arbitrary
#' classes to objects in the parent. Malformed encodings are errors.
#'
#' @param x A value parsed with `jsonlite::fromJSON(simplifyVector = FALSE)`.
#' @return The decoded value.
#' @keywords internal
ipc_decode_value <- function(x) {
  if (!is.list(x)) return(x)
  if (!is.null(names(x)) && "__securer__" %in% names(x)) {
    if (!identical(x[["__securer__"]], "data.frame")) {
      stop("Malformed IPC message: unknown encoded value", call. = FALSE)
    }
    return(ipc_decode_data_frame(x))
  }
  lapply(x, ipc_decode_value)
}

#' @rdname ipc_decode_value
#' @keywords internal
ipc_decode_data_frame <- function(x) {
  bad <- function() {
    stop("Malformed IPC message: invalid data frame encoding", call. = FALSE)
  }
  col_names <- unlist(x[["names"]])
  columns <- x[["columns"]]
  if (is.null(col_names)) col_names <- character()
  if (is.null(columns)) columns <- list()
  if (!is.character(col_names) || !is.list(columns) ||
      length(col_names) != length(columns)) {
    bad()
  }
  columns <- lapply(columns, ipc_decode_column)

  rn <- x[["row_names"]]
  if (is.list(rn) && !is.null(rn[["compact"]])) {
    n <- rn[["compact"]]
    if (!is.numeric(n) || length(n) != 1L || is.na(n)) bad()
    row_names <- c(NA_integer_, as.integer(n))
    nrow <- abs(as.integer(n))
  } else {
    row_names <- ipc_decode_column(rn)
    if (!is.atomic(row_names)) bad()
    nrow <- length(row_names)
  }
  if (any(lengths(columns) != nrow)) bad()

  cls <- intersect(unlist(x[["class"]]), c("tbl_df", "tbl", "data.frame"))
  if (!"data.frame" %in% cls) cls <- "data.frame"
  names(columns) <- col_names
  attr(columns, "row.names") <- row_names
  class(columns) <- cls
  columns
}

#' @rdname ipc_decode_value
#' @keywords internal
ipc_decode_column <- function(x) {
  bad <- function() {
    stop("Malformed IPC message: invalid data frame column", call. = FALSE)
  }
  if (!is.list(x) || !identical(x[["__securer__"]], "column") ||
      !is.character(x[["type"]]) || length(x[["type"]]) != 1L) {
    bad()
  }
  values <- x[["values"]]
  if (is.null(values)) values <- list()
  if (!is.list(values)) values <- list(values)

  if (identical(x[["type"]], "list")) {
    return(lapply(values, ipc_decode_value))
  }

  # jsonlite writes NA as null (logical, character) or as the strings
  # "NA", "NaN", "Inf", "-Inf" (numbers). Map those back explicitly.
  special <- c("NA" = NA_real_, "NaN" = NaN, "Inf" = Inf, "-Inf" = -Inf)
  one <- switch(x[["type"]],
    logical = function(v) {
      if (is.null(v)) NA else if (is.logical(v) && length(v) == 1L) v else bad()
    },
    character = function(v) {
      if (is.null(v)) NA_character_
      else if (is.character(v) && length(v) == 1L) v else bad()
    },
    integer = function(v) {
      if (is.null(v) || identical(v, "NA")) NA_integer_
      else if (is.numeric(v) && length(v) == 1L) as.integer(v) else bad()
    },
    double = function(v) {
      if (is.null(v)) NA_real_
      else if (is.character(v) && length(v) == 1L && v %in% names(special))
        special[[v]]
      else if (is.numeric(v) && length(v) == 1L) as.double(v) else bad()
    },
    bad()
  )
  out <- vapply(values, one, vector(x[["type"]], 1L), USE.NAMES = FALSE)

  allowed <- c("factor", "ordered", "Date", "POSIXct", "POSIXt", "difftime")
  cls <- intersect(unlist(x[["class"]]), allowed)
  if ("factor" %in% cls) {
    lev <- unlist(x[["levels"]])
    if (is.null(lev)) lev <- character()
    if (!is.character(lev) || !is.integer(out) ||
        any(out < 1L | out > length(lev), na.rm = TRUE)) {
      bad()
    }
    attr(out, "levels") <- lev
  }
  if ("POSIXct" %in% cls && is.character(x[["tzone"]])) {
    attr(out, "tzone") <- x[["tzone"]]
  }
  if ("difftime" %in% cls && is.character(x[["units"]]) &&
      length(x[["units"]]) == 1L) {
    attr(out, "units") <- x[["units"]]
  }
  if (length(cls) > 0L) class(out) <- cls
  out
}

#' Serialize an IPC message to a JSON line
#'
#' @param msg A list to send.
#' @return A JSON string (without the trailing newline).
#' @keywords internal
ipc_to_json <- function(msg) {
  # digits = NA keeps 15 significant digits instead of jsonlite's default
  # of 4 decimals, so numbers aren't silently rounded in transit.
  as.character(jsonlite::toJSON(
    ipc_encode_value(msg), auto_unbox = TRUE, digits = NA, null = "null"
  ))
}

#' Write one line to an IPC connection
#'
#' `processx::conn_write()` writes only as much as the socket buffer takes
#' (about 8 KB on macOS) and returns the rest. This keeps writing until the
#' whole line is sent.
#'
#' @param conn A connection object
#' @param line A string, without the trailing newline
#' @param timeout Timeout in milliseconds
#' @return Invisible `NULL`.
#' @keywords internal
ipc_write_line <- function(conn, line, timeout = 30000L) {
  deadline <- Sys.time() + timeout / 1000
  left <- processx::conn_write(conn, paste0(line, "\n"))
  while (length(left) > 0) {
    if (Sys.time() > deadline) {
      stop("Timeout writing IPC message", call. = FALSE)
    }
    Sys.sleep(0.001)
    left <- processx::conn_write(conn, left)
  }
  invisible(NULL)
}

#' Read one line from an IPC connection, if one arrives in time
#'
#' A message bigger than the socket buffer arrives in pieces. The pieces are
#' kept in `buffer` (an environment, one per connection) until a full line
#' is in. Reading stops with an error as soon as the pending data passes
#' `max_size`, before the rest is pulled into memory.
#'
#' @param conn A connection object
#' @param buffer An environment holding this connection's unread data
#' @param timeout Timeout in milliseconds
#' @param max_size Largest message allowed, in bytes
#' @return The line, or `NULL` if none completed in time or the connection
#'   was closed (then `buffer$closed` is `TRUE`).
#' @keywords internal
ipc_poll_line <- function(conn, buffer, timeout,
                          max_size = ipc_max_message_size) {
  if (is.null(buffer$data)) buffer$data <- ""
  deadline <- Sys.time() + timeout / 1000
  repeat {
    nl <- regexpr("\n", buffer$data, fixed = TRUE)
    if (nl > 0) {
      line <- substr(buffer$data, 1L, nl - 1L)
      buffer$data <- substr(buffer$data, nl + 1L, nchar(buffer$data))
      if (nchar(line, type = "bytes") > max_size) {
        stop("IPC message too large (", nchar(line, type = "bytes"),
             " bytes, max ", max_size, ")", call. = FALSE)
      }
      return(line)
    }
    if (nchar(buffer$data, type = "bytes") > max_size) {
      buffer$data <- ""
      stop("IPC message too large (more than ", max_size, " bytes)",
           call. = FALSE)
    }
    remaining <- as.numeric(difftime(deadline, Sys.time(), units = "secs"))
    remaining_ms <- max(0L, as.integer(remaining * 1000))
    if (processx::poll(list(conn), remaining_ms)[[1]] != "ready") {
      return(NULL)
    }
    chunk <- processx::conn_read_chars(conn)
    if (!nzchar(chunk) && !processx::conn_is_incomplete(conn)) {
      buffer$closed <- TRUE
      return(NULL)
    }
    buffer$data <- paste0(buffer$data, chunk)
    if (remaining_ms <= 0L && !nzchar(chunk)) return(NULL)
  }
}

#' Write a message to an IPC connection
#'
#' Serializes a list to JSON and writes it as a single newline-terminated
#' line, looping until all of it is written.
#'
#' @param conn A connection object
#' @param msg A list to serialize and send
#' @param timeout Timeout in milliseconds (default 30000)
#' @return Invisible `NULL`; called for its side effect of writing to the
#'   connection.
#' @keywords internal
ipc_write_message <- function(conn, msg, timeout = 30000L) {
  ipc_write_line(conn, ipc_to_json(msg), timeout)
}

#' Read a message from an IPC connection
#'
#' Reads a single newline-terminated JSON line from the connection, with
#' timeout. Returns parsed list. Raises error on timeout.
#'
#' @param conn A connection object
#' @param timeout Timeout in milliseconds (default 30000)
#' @param max_size Largest message allowed, in bytes
#' @param buffer Environment holding unread data for `conn`. Pass the same
#'   one on every read from a connection so partial data isn't lost.
#' @return A parsed list from the JSON message
#' @keywords internal
ipc_read_message <- function(conn, timeout = 30000L,
                             max_size = ipc_max_message_size,
                             buffer = new.env(parent = emptyenv())) {
  line <- ipc_poll_line(conn, buffer, timeout, max_size)
  if (isTRUE(buffer$closed)) {
    stop("Empty message received on IPC connection", call. = FALSE)
  }
  if (is.null(line)) {
    stop("Timeout waiting for IPC message", call. = FALSE)
  }
  if (!nzchar(line)) {
    stop("Empty message received on IPC connection", call. = FALSE)
  }
  ipc_decode_value(jsonlite::fromJSON(line, simplifyVector = FALSE))
}
