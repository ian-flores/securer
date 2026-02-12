#' Create a tool definition
#'
#' Defines a named tool with a function implementation and typed argument
#' metadata. Tool objects are passed to [SecureSession] or [execute_r()] so
#' that code running in the sandboxed child process can call the tool by name
#' and the parent process executes the actual function.
#'
#' @param name Character, the tool name (must be non-empty).
#' @param description Character, description of what the tool does.
#' @param fn Function that implements the tool.
#' @param args Named list mapping argument names to type strings
#'   (e.g. `list(city = "character")`). Used to generate wrapper functions
#'   in the child process with the correct formal arguments.
#' @return A `securer_tool` object (a list with class `"securer_tool"`).
#'
#' @examples
#' tool <- securer_tool(
#'   "add", "Add two numbers",
#'   fn = function(a, b) a + b,
#'   args = list(a = "numeric", b = "numeric")
#' )
#' tool$name
#' # "add"
#'
#' @export
securer_tool <- function(name, description, fn, args = list()) {
  stopifnot(
    is.character(name), nchar(name) > 0,
    is.character(description),
    is.function(fn),
    is.list(args)
  )

  # Validate tool name is a valid R identifier (prevents code injection
  # since names are interpolated into eval'd code strings)
  if (!grepl("^[A-Za-z.][A-Za-z0-9_.]*$", name)) {
    stop("Tool name must be a valid R identifier: ", sQuote(name), call. = FALSE)
  }

  # Validate argument names are valid R identifiers
  arg_names <- names(args)
  if (length(arg_names) > 0) {
    bad <- arg_names[!grepl("^[A-Za-z.][A-Za-z0-9_.]*$", arg_names)]
    if (length(bad) > 0) {
      stop(
        "Argument names must be valid R identifiers: ",
        paste(sQuote(bad), collapse = ", "),
        call. = FALSE
      )
    }
  }

  structure(
    list(name = name, description = description, fn = fn, args = args),
    class = "securer_tool"
  )
}

#' Validate a list of tools
#'
#' Accepts either a named list of bare functions (legacy format from
#' increment 1) or a list of [securer_tool()] objects. Returns a named
#' list with two components: `fns` (tool functions keyed by name) and
#' `arg_meta` (expected argument names keyed by tool name).
#'
#' @param tools List of `securer_tool` objects or a named list of functions
#' @return A list with `fns` (named list of functions) and `arg_meta`
#'   (named list of character vectors of expected arg names, `NULL` for
#'   legacy tools without metadata)
#' @keywords internal
validate_tools <- function(tools) {
  if (length(tools) == 0) return(list(fns = list(), arg_meta = list()))

  # Accept named list of bare functions (legacy / backward compat)
  if (is.list(tools) && !is.null(names(tools)) &&
      all(vapply(tools, is.function, logical(1)))) {
    # --- Deprecation warning (T2 fix) ---
    .Deprecated(
      msg = paste(
        "Passing tools as a named list of functions is deprecated.",
        "Use securer_tool() objects instead."
      )
    )
    # --- Legacy tool name validation (T2 fix) ---
    tool_names <- names(tools)
    bad_names <- tool_names[!grepl("^[A-Za-z.][A-Za-z0-9_.]*$", tool_names)]
    if (length(bad_names) > 0) {
      stop(
        "Legacy tool names must be valid R identifiers: ",
        paste(sQuote(bad_names), collapse = ", "),
        call. = FALSE
      )
    }
    # No arg metadata available for legacy tools
    arg_meta <- lapply(tools, function(f) NULL)
    return(list(fns = tools, arg_meta = arg_meta))
  }

  # Otherwise expect securer_tool objects
  for (tool in tools) {
    if (!inherits(tool, "securer_tool")) {
      stop("Each tool must be created with securer_tool()", call. = FALSE)
    }
  }

  # Check for duplicate names
  names_vec <- vapply(tools, function(t) t$name, character(1))
  if (anyDuplicated(names_vec)) {
    stop(
      "Duplicate tool names: ",
      paste(names_vec[duplicated(names_vec)], collapse = ", "),
      call. = FALSE
    )
  }

  # Return named list of functions + arg metadata.
  # For tools with args = list() (explicitly no arguments),
  # store character(0) — not NULL — so the parent can distinguish
  # "no metadata" (legacy) from "zero args allowed" (T4 fix).
  fns <- lapply(tools, function(t) t$fn)
  names(fns) <- names_vec
  arg_meta <- lapply(tools, function(t) {
    nm <- names(t$args)
    if (is.null(nm)) character(0) else nm
  })
  names(arg_meta) <- names_vec
  list(fns = fns, arg_meta = arg_meta)
}

#' Generate wrapper code for tools in the child process
#'
#' For each [securer_tool()] object, generates an R function in the child's
#' global environment that delegates to `.securer_call_tool()` with the
#' tool name and arguments.
#'
#' @param tools List of `securer_tool` objects
#' @return Character string of R code that creates wrapper functions
#' @keywords internal
generate_tool_wrappers <- function(tools) {
  if (length(tools) == 0) return("")

  code_parts <- vapply(tools, function(tool) {
    arg_names <- names(tool$args)
    if (length(arg_names) == 0) {
      # No arguments: generate a zero-argument wrapper (T4 fix).
      # Using function() instead of function(...) ensures the child
      # rejects extra arguments at the R level as defense in depth.
      formals_str <- ""
      call_args <- ""
      validation_code <- ""
    } else {
      formals_str <- paste(arg_names, collapse = ", ")
      call_args <- paste0(
        ", ",
        paste(paste0(arg_names, " = ", arg_names), collapse = ", ")
      )
      validation_code <- generate_type_checks(tool$name, tool$args)
    }
    if (nzchar(validation_code)) {
      fn_code <- sprintf(
        '%s <- function(%s) {\n%s\n  .securer_call_tool("%s"%s)\n}',
        tool$name, formals_str, validation_code, tool$name, call_args
      )
    } else {
      fn_code <- sprintf(
        '%s <- function(%s) .securer_call_tool("%s"%s)',
        tool$name, formals_str, tool$name, call_args
      )
    }
    # Lock the binding so child code cannot overwrite the tool wrapper
    paste0(fn_code, "\n", sprintf('lockBinding("%s", globalenv())', tool$name))
  }, character(1))

  paste(code_parts, collapse = "\n")
}

#' Map of type annotation strings to R type-checking functions
#'
#' @keywords internal
type_check_map <- c(
  numeric = "is.numeric",
  character = "is.character",
  logical = "is.logical",
  integer = "is.integer",
  list = "is.list",
  data.frame = "is.data.frame"
)

#' Generate type validation code for tool arguments
#'
#' Produces R code as a character string that checks each argument's type
#' against its declared type annotation. Arguments without type annotations
#' are skipped.
#'
#' @param tool_name Character, the tool name (for error messages)
#' @param args Named list mapping argument names to type strings
#' @return Character string of R code performing type checks (may be empty)
#' @keywords internal
generate_type_checks <- function(tool_name, args) {
  arg_names <- names(args)
  checks <- character(0)
  for (nm in arg_names) {
    type_str <- args[[nm]]
    if (is.null(type_str) || !nzchar(type_str)) next
    check_fn <- type_check_map[type_str]
    if (is.na(check_fn)) next
    checks <- c(checks, sprintf(
      '  if (!%s(%s)) stop("Tool \'%s\': argument \'%s\' must be %s, got ", class(%s)[1], call. = FALSE)',
      check_fn, nm, tool_name, nm, type_str, nm
    ))
  }
  paste(checks, collapse = "\n")
}
