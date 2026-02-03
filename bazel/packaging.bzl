"""Helpers for creating packaging artifacts."""

load("@bazel_lib//lib:expand_template.bzl", "expand_template")

def mtree_from_lines(name, contents, data, **kwargs):
    """Creates a named mtree file target from a list of mtree specification lines.

    Args:
        name: name of the target; output file will be `[name].txt`.
        contents: list of mtree specification lines. Values may use $(location)
            for files listed in data.
        data: list of file labels referenced via $(location) in contents.
        **kwargs: additional arguments forwarded to expand_template.
    """
    expand_template(
        name = name,
        out = name + ".txt",
        data = data,
        substitutions = {
            "{content}": "\n".join(contents),
        },
        template = ["#mtree", "{content}", ""],
        **kwargs
    )
