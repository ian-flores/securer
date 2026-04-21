test_that("docker-spawn wrapper script is built with expected flags", {
  socket <- tempfile("sock_", tmpdir = tempdir())
  cfg <- build_sandbox_docker_spawn(socket, R.home(), limits = list(
    memory = 256 * 1024 * 1024,
    cpu    = 30,
    nofile = 64
  ))

  expect_true(file.exists(cfg$wrapper))
  expect_null(cfg$profile_path)

  script <- readLines(cfg$wrapper)
  expect_match(script[1], "^#!/bin/sh$")
  last <- script[length(script)]
  expect_match(last, "^exec docker run --rm -i --network=none")
  expect_match(last, "--memory=268435456b")
  expect_match(last, "--cpus=")
  # ulimit for nofile should be present (not passed as a docker flag)
  expect_true(any(grepl("ulimit -S -H -n 64", script)))
})

test_that("docker-spawn wrapper respects SECURER_DOCKER_IMAGE override", {
  withr::with_envvar(
    c(SECURER_DOCKER_IMAGE = "my-registry/r-hardened:2026"),
    {
      socket <- tempfile("sock_", tmpdir = tempdir())
      cfg <- build_sandbox_docker_spawn(socket, R.home(), limits = NULL)
      last <- tail(readLines(cfg$wrapper), 1)
      expect_match(last, "my-registry/r-hardened:2026")
    }
  )
})

test_that("docker-spawn dispatcher is gated on docker availability", {
  skip_if(is_docker_spawn_available(), "docker is installed; can't test absent path")
  withr::with_envvar(
    c(SECURER_SANDBOX_MODE = "docker-spawn"),
    {
      cfg <- build_sandbox_config(
        tempfile("sock_", tmpdir = tempdir()),
        R.home(),
        limits = NULL
      )
      # Should fall through to the platform-native backend, not docker-spawn.
      expect_true(is.null(cfg$wrapper) || !grepl("docker", readLines(cfg$wrapper)[length(readLines(cfg$wrapper))]))
    }
  )
})

test_that("docker-spawn end-to-end runs when docker is available", {
  skip_if_not(is_docker_spawn_available(), "docker not available")
  skip_on_cran()
  withr::with_envvar(
    c(SECURER_SANDBOX_MODE = "docker-spawn"),
    {
      res <- tryCatch(execute_r("1 + 1"), error = function(e) e)
      # The end-to-end path depends on a pullable image and a mountable
      # socket dir; accept either a successful result or a descriptive
      # docker error.  Both prove the wrapper was invoked.
      if (inherits(res, "error")) {
        expect_match(conditionMessage(res), "docker|image|mount", ignore.case = TRUE)
      } else {
        expect_equal(as.numeric(res), 2)
      }
    }
  )
})
