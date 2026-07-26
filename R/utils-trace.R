# Internal tracing helpers -- not exported
# OpenTelemetry (via the otel package) is a soft dependency (Suggests only)

# Innermost span started by .with_span(), so that .span_event() can attach
# events to it without relying on otel internals.
the_trace <- new.env(parent = emptyenv())

.trace_active <- function() {
  requireNamespace("otel", quietly = TRUE) &&
    otel::is_tracing_enabled(otel_tracer_name)
}

# Evaluate `expr` inside an active span named `name`.  The span ends
# automatically when .with_span() returns.  When tracing is disabled (or
# otel is not installed), `expr` is evaluated unchanged.
.with_span <- function(name, expr, attributes = NULL) {
  if (!.trace_active()) {
    return(expr)
  }
  span <- otel::start_local_active_span(
    name,
    attributes = if (length(attributes)) otel::as_attributes(attributes),
    tracer = otel_tracer_name
  )
  prev <- the_trace$span
  the_trace$span <- span
  on.exit(the_trace$span <- prev, add = TRUE)
  expr
}

# Attach an event to the innermost .with_span() span.  No-op when tracing
# is disabled or no securer span is active.
.span_event <- function(name, data = list()) {
  span <- the_trace$span
  if (!is.null(span) && .trace_active()) {
    span$add_event(name, attributes = otel::as_attributes(data))
  }
  invisible(NULL)
}
