# CXXFLAGS that we need for Bazel specifically. Not present in the Makefile
CXXFLAGS_COMMON_BAZEL = [
  # TODO: rules_distroless introduces a bunch of include directories that don't exist
  # so we need to disable that warning or else -Werror will fail the build.
  "-Wno-missing-include-dirs",
]

# CXXFLAGS from the Makefile
CXXFLAGS_COMMON_MAKEFILE = [
  "-ansi",
  "-fPIC",
  "-pipe",
  "-std=c++14",
  "-Wall",
  "-Wcast-align",
  "-Wcast-qual",
  "-Wconversion",
  "-Wdisabled-optimization",
  "-Werror",
  "-Wextra",
  "-Wfloat-equal",
  "-Wformat=2",
  "-Wformat-nonliteral",
  "-Wformat-security",
  "-Wformat-y2k",
  "-Wimport",
  "-Winit-self",
  "-Wno-inline",
  "-Winvalid-pch",
  "-Wmissing-field-initializers",
  "-Wmissing-format-attribute",
  "-Wmissing-include-dirs",
  "-Wmissing-noreturn",
  "-Wno-aggregate-return",
  "-Wno-padded",
  "-Wno-switch-enum",
  "-Wno-unused-parameter",
  "-Wpacked",
  "-Wpointer-arith",
  "-Wredundant-decls",
  "-Wshadow",
  "-Wstack-protector",
  "-Wstrict-aliasing=3",
  "-Wswitch",
  "-Wswitch-default",
  "-Wunreachable-code",
  "-Wunused",
  "-Wvariadic-macros",
  "-Wwrite-strings",
  "-Wno-switch-default",
  "-Wconversion",
  "-Wno-psabi",
]

CXXFLAGS_COMMON = CXXFLAGS_COMMON_MAKEFILE + CXXFLAGS_COMMON_BAZEL

# TODO: Fill these out when we support debugging and code coverage
CODE_COVERAGE_CFLAGS = []
CODE_COVERAGE_CPPFLAGS = []
CODE_COVERAGE_CXXFLAGS = []
CODE_COVERAGE_LIBS = []
DBGFLAGS = []
