# Internal tracing helpers -- not exported
# securetrace is a soft dependency (Suggests only)

.trace_active <- function() {
  requireNamespace("securetrace", quietly = TRUE) &&
    !is.null(securetrace::current_trace())
}

.span_event <- function(name, data = list()) {
  if (.trace_active()) {
    span <- securetrace::current_span()
    if (!is.null(span)) {
      span$add_event(securetrace::trace_event(name, data))
    }
  }
  invisible(NULL)
}
