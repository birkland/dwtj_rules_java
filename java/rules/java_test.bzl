'''Defines the `java_test` rule.
'''

load("@dwtj_rules_java//java:providers/JavaAgentInfo.bzl", "JavaAgentInfo")
load("@dwtj_rules_java//java:providers/JavaCompilationInfo.bzl", "JavaCompilationInfo")
load("@dwtj_rules_java//java:providers/JavaDependencyInfo.bzl", "JavaDependencyInfo")

load("@dwtj_rules_java//java:rules/common/actions/compile_and_jar_java_sources.bzl", "compile_and_jar_java_target")
load("@dwtj_rules_java//java:rules/common/actions/write_java_run_script.bzl", "write_java_run_script_from_ctx")
load("@dwtj_rules_java//java:rules/common/extract/toolchain_info.bzl", "extract_java_runtime_toolchain_info", "extract_java_executable")
load(
    "@dwtj_rules_java//java:rules/common/providers.bzl",
    "singleton_java_dependency_info",
    "make_legacy_java_info",
)

# NOTE(dwtj): This is very similar to `_java_binary_impl()`.
def _java_test_impl(ctx):
    java_compilation_info = compile_and_jar_java_target(ctx)
    java_dependency_info = singleton_java_dependency_info(
        java_compilation_info.class_files_output_jar,
    )
    java_execution_info, run_script, class_path_args_file, jvm_flags_args_file, run_time_jars = write_java_run_script_from_ctx(
        ctx,
        java_dependency_info,
        extract_java_runtime_toolchain_info(ctx),
    )

    return [
        DefaultInfo(
            files = depset([java_compilation_info.class_files_output_jar]),
            executable = run_script,
            runfiles = ctx.runfiles(
                files = [
                    extract_java_executable(ctx),
                    run_script,
                    class_path_args_file,
                    jvm_flags_args_file,
                ],
                transitive_files = run_time_jars
            ),
        ),
        java_compilation_info,
        java_execution_info,
        make_legacy_java_info(java_compilation_info, ctx.attr.deps),
    ]

java_test = rule(
    implementation = _java_test_impl,
    test = True,
    attrs = {
        "srcs": attr.label_list(
            # TODO(dwtj): Consider supporting empty `srcs` list once `exports`
            #  is supported.
            allow_empty = False,
            doc = "A list of Java source files whose derived class files should be included in this test (and any of its dependents).",
            allow_files = [".java"],
            default = list(),
        ),
        "main_class": attr.string(
            mandatory = True,
        ),
        "deps": attr.label_list(
            providers = [
                JavaDependencyInfo,
                JavaInfo,
            ],
            default = list()
        ),
        "additional_jar_manifest_attributes": attr.string_list(
            doc = "A list of strings; each will be added as a line of the output JAR's manifest file. The JAR's `Main-Class` header is automatically set according to the target's `main_class` attribute.",
            default = list(),
        ),
        # TODO(dwtj): A dict is used here in order to support Java agent
        #  options, but this causes two problems. First, it means that a single
        #  Java agent cannot be listed multiple times. Second, the order of
        #  agents is lost. These are problems because according to the
        #  [`java.lang.instrument` Javadoc][1], agents can be listed multiple
        #  times and their order dictates the sequence by which `premain()`
        #  functions are called. Thus, this design doesn't support all use cases
        #  provided by the `java` command line interface.
        #
        #  Unfortunately, I don't immediately see an alternative to this use of
        #  dict. At least these use cases are probably rare.
        #
        #  ---
        #
        #  1: https://docs.oracle.com/en/java/javase/14/docs/api/java.instrument/java/lang/instrument/package-summary.html
        "java_agents": attr.label_keyed_string_dict(
            doc = "A dict from `java_agent` targets to strings. Each key is a `java_agent` target with which this target should be run; each value is an option string to be passed to that Java agent.",
            providers = [
                JavaAgentInfo,
                JavaDependencyInfo,
            ],
            default = dict(),
        ),
    },
    provides = [
        JavaCompilationInfo,
        JavaInfo,
    ],
    toolchains = [
        "@dwtj_rules_java//java/toolchains/java_compiler_toolchain:toolchain_type",
        "@dwtj_rules_java//java/toolchains/java_runtime_toolchain:toolchain_type",
    ],
)