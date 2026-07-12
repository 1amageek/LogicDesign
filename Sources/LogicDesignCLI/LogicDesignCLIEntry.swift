import Foundation

@main
struct LogicDesignCLIEntry {
    static func main() async {
        let code = await LogicDesignCLI.run(arguments: Array(CommandLine.arguments.dropFirst()))
        Foundation.exit(Int32(code))
    }
}
