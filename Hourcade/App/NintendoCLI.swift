import Foundation

struct NintendoGame: Decodable, Identifiable, Sendable {
    let name: String
    let imageUri: String
    let shopUri: String
    let totalPlayTime: Int
    let firstPlayedAt: Int

    var id: String { shopUri.isEmpty ? name : shopUri }
}

enum NintendoCLI {
    static func load(executablePath: String) async throws -> [NintendoGame] {
        let path = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) else {
            throw NintendoError.missingExecutable
        }
        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["nso", "play-activity", "--json"]
            let output = Pipe()
            let errors = Pipe()
            process.standardOutput = output
            process.standardError = errors
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw NintendoError.commandFailed
            }
            guard let games = try? JSONDecoder().decode([NintendoGame].self, from: data) else {
                throw NintendoError.invalidResponse
            }
            return games
        }.value
    }
}

private enum NintendoError: LocalizedError {
    case missingExecutable, commandFailed, invalidResponse
    var errorDescription: String? {
        switch self {
        case .missingExecutable: "请先选择已安装的 nxapi 可执行文件"
        case .commandFailed: "nxapi 无法读取游玩记录；请先在终端执行 nxapi nso auth 完成登录"
        case .invalidResponse: "nxapi 返回的数据格式无法读取"
        }
    }
}
