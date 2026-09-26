import Foundation

/// The dependency boundary, checked by doctor: every `.package(path:)` of the owner's apps and packages
/// must lead to an existing `packages/<name>`. An app then cannot depend on another app or on a brick.
enum DependencyChecks {
    static func check(_ repository: Repository) -> DoctorCheck {
        let problems = self.problems(in: repository.root)
        guard problems.isEmpty else {
            return DoctorCheck(
                name: "path-deps",
                status: .fail,
                detail: "path 의존은 packages/<이름> 만 가리킬 수 있습니다: \(problems.joined(separator: ", "))"
            )
        }
        return DoctorCheck(name: "path-deps", status: .ok, detail: "apps/, packages/ 의 path 의존이 모두 packages/ 안을 가리킴")
    }

    static func problems(in root: URL) -> [String] {
        var problems: [String] = []
        for group in ["apps", "packages"] {
            for name in FileTree.subdirectories(of: root.appending(path: group)) {
                let directory = "\(group)/\(name)"
                let manifestURL = root.appending(path: "\(directory)/Package.swift")
                guard let manifest = try? String(contentsOf: manifestURL, encoding: .utf8) else {
                    continue
                }
                for path in PackageDependencies.declared(in: manifest).paths {
                    guard let package = PackageDependencies.packageName(resolving: path, from: directory) else {
                        problems.append("\(directory) 의 '\(path)' 가 packages/ 밖을 가리킴")
                        continue
                    }
                    if !FileTree.itemExists(root.appending(path: "packages/\(package)/Package.swift")) {
                        problems.append("\(directory) 의 '\(path)' 가 가리키는 packages/\(package) 가 없음")
                    }
                }
            }
        }
        return problems
    }
}
