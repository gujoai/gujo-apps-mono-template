import Foundation

/// doctor checks for tenants and bricks.
enum BrickChecks {
    static func checks(_ repository: Repository) -> [DoctorCheck] {
        var checks = [tenantCheck(repository)]
        let lock: BrickLock
        do {
            lock = try BrickLock.load(from: repository.root)
        } catch let error as RepoError {
            return checks + [DoctorCheck(name: "bricks", status: .fail, detail: error.message)]
        } catch {
            return checks + [DoctorCheck(name: "bricks", status: .fail, detail: error.localizedDescription)]
        }
        checks.append(lockCheck(lock, in: repository))
        let registered = Set(((try? repository.loadConfig())?.tenants ?? [:]).keys)
        let unregistered = lock.tenants.keys.filter { !registered.contains($0) }.sorted()
        if !unregistered.isEmpty {
            checks.append(
                DoctorCheck(
                    name: "bricks-tenants",
                    status: .warn,
                    detail: "\(Tenants.lockFileName) 의 테넌트가 repo.json 의 tenants 에 없습니다: "
                        + "\(unregistered.joined(separator: ", ")). 받은 블록은 그대로 쓸 수 있지만 update 는 할 수 없습니다."
                )
            )
        }
        // A brick's structure is the tenant's responsibility, so problems only warn.
        for app in repository.brickApps() {
            let check = AppStructure.check(appDirectory: repository.directory(of: app), name: "brick \(app)")
            if check.status == .fail {
                checks.append(
                    DoctorCheck(name: check.name, status: .warn, detail: "\(check.detail) (테넌트가 고칠 문제입니다)")
                )
            }
        }
        return checks
    }

    static func tenantCheck(_ repository: Repository) -> DoctorCheck {
        let tenants = (try? repository.loadConfig())?.tenants ?? [:]
        let invalid = tenants.keys.filter { !Tenants.isValidName($0) }.sorted()
        guard invalid.isEmpty else {
            return DoctorCheck(
                name: "tenants",
                status: .fail,
                detail: "repo.json 의 tenants 에 이름 형식이 틀린 항목이 있습니다: \(invalid.joined(separator: ", ")). "
                    + "소문자로 시작하고 소문자·숫자·하이픈만 씁니다."
            )
        }
        let detail = tenants.isEmpty ? "등록된 테넌트 없음" : "등록된 테넌트 \(tenants.keys.sorted().joined(separator: ", "))"
        return DoctorCheck(name: "tenants", status: .ok, detail: detail)
    }

    /// `bricks.lock` and `bricks/` must describe the same apps and packages.
    static func lockCheck(_ lock: BrickLock, in repository: Repository) -> DoctorCheck {
        let problems = mismatches(lock, bricksDirectory: repository.bricksDirectory)
        guard problems.isEmpty else {
            return DoctorCheck(
                name: "bricks",
                status: .fail,
                detail: "\(Tenants.lockFileName) 과 \(Tenants.directory)/ 가 어긋납니다: \(problems.joined(separator: ", ")). "
                    + "swift run repo brick 명령으로만 바꾸고, 어긋났으면 git 으로 되돌리세요."
            )
        }
        guard !lock.tenants.isEmpty else {
            return DoctorCheck(name: "bricks", status: .ok, detail: "받은 블록 없음")
        }
        let apps = lock.tenants.values.map(\.apps.count).reduce(0, +)
        return DoctorCheck(
            name: "bricks",
            status: .ok,
            detail: "테넌트 \(lock.tenants.count)곳에서 받은 앱 \(apps)개가 \(Tenants.lockFileName) 과 일치"
        )
    }

    static func mismatches(_ lock: BrickLock, bricksDirectory: URL) -> [String] {
        var problems: [String] = []
        for tenant in FileTree.subdirectories(of: bricksDirectory) where lock.tenants[tenant] == nil {
            problems.append("\(Tenants.path(tenant))/ 가 기록에 없음")
        }
        for (tenant, entry) in lock.tenants.sorted(by: { $0.key < $1.key }) {
            let tenantDirectory = bricksDirectory.appending(path: tenant)
            for (group, recorded) in [("apps", entry.apps), ("packages", entry.packages)] {
                let present = FileTree.subdirectories(of: tenantDirectory.appending(path: group))
                for name in recorded where !present.contains(name) {
                    problems.append("\(Tenants.path(tenant))/\(group)/\(name) 없음")
                }
                for name in present where !recorded.contains(name) {
                    problems.append("\(Tenants.path(tenant))/\(group)/\(name) 가 기록에 없음")
                }
            }
        }
        return problems
    }
}
