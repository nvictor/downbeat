import ArgumentParser
import LogicKit

struct Check: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Check that Logic Pro can be controlled.")

    @Flag(help: "Print JSON.")
    var json = false

    func run() throws {
        let environment = LogicApp.environment()
        if json {
            try printJSON(environment)
        } else {
            let unknown = "unknown"
            print("Accessibility: \(environment.accessibilityTrusted ? "granted" : "missing")")
            print("Logic Pro:     \(environment.running ? "running" : "not running") \(environment.version ?? "")")
            print("Language:      \(environment.language ?? unknown)")
            print("Project:       \(environment.projectPath ?? unknown)")
            for problem in environment.problems { print("! \(problem)") }
        }
        if !environment.problems.isEmpty { throw ExitCode.failure }
    }
}
