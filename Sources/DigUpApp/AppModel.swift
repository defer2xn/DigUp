import AppKit
import Observation

/// State the menubar, the panel and the windows share. Engine updates arrive on the main thread.
@Observable
final class AppModel {
    var status = EngineStatus()
    var settings: AppSettings
    var hotkey: KeyCombo?
    let download: ModelDownload
    /// A newer DigUp the daily check found ("0.6.1"), until you open it (`Updates`).
    var updateAvailable: String?

    init(settings: AppSettings, download: ModelDownload) {
        self.settings = settings
        self.download = download
    }

    var hasFolders: Bool { !settings.roots.isEmpty }
    /// Code search is on (there are code folders).
    var hasCode: Bool { !settings.codeRoots.isEmpty }

    /// One line for the menu and the windows: what the index is doing.
    var statusLine: String {
        let status = self.status
        guard hasFolders else { return String(localized: "No folders chosen yet") }
        switch status.activity {
        case .starting: return String(localized: "Starting…")
        case .failed(let problem): return "⚠︎ \(problem)"
        case .syncing: return String(localized: "Checking folders…")
        case .indexing(let done, let total):
            let percent = total > 0 ? Int((Double(done) / Double(total) * 100).rounded(.down)) : 0
            return String(localized: "Indexing \(percent)% · \(done.formatted()) of \(total.formatted())")
        case .finishing(let done, let total, let files):
            let percent = total > 0 ? Int((Double(done) / Double(total) * 100).rounded(.down)) : 0
            let which = files == 0 ? String(localized: "long files")
                : files == 1 ? String(localized: "\(files.formatted()) long file")
                : String(localized: "\(files.formatted()) long files")
            return String(localized: "Reading the rest of \(which) · \(percent)%")
        case .idle:
            if let line = downloadLine { return line }
            if let code = status.code.indexing, code.total > 0 {
                let percent = Int((Double(code.done) / Double(code.total) * 100).rounded(.down))
                return String(localized: "Indexing code \(percent)% · \(code.done.formatted()) of \(code.total.formatted())")
            }
            let waiting = status.pending == 1 ? String(localized: "\(status.pending.formatted()) file waiting")
                : String(localized: "\(status.pending.formatted()) files waiting")
            if status.pending > 0, status.paused { return String(localized: "Paused · \(waiting)") }
            if let until = status.heldUntil, !status.paused {
                // Outside the set hours: what's known to wait, and when indexing starts again.
                let when = String(localized: "indexing from \(until.formatted(date: .omitted, time: .shortened))")
                if status.pending > 0 { return "\(waiting) · \(when)" }
                let indexed = status.searchable == 1 ? String(localized: "\(status.searchable.formatted()) file indexed")
                    : String(localized: "\(status.searchable.formatted()) files indexed")
                return "\(indexed) · \(when)"
            }
            if status.pending > 0, let reason = status.waitingFor { return "\(waiting) · \(reason)" }
            if status.pending > 0 { return String(localized: "\(waiting) to be indexed") }
            if status.unfinished > 0 {
                let rest = status.unfinished == 1
                    ? String(localized: "\(status.unfinished.formatted()) long file to finish")
                    : String(localized: "\(status.unfinished.formatted()) long files to finish")
                if status.paused { return String(localized: "Paused · \(rest)") }
                if let reason = status.waitingFor { return "\(rest) · \(reason)" }
            }
            let indexed = status.searchable == 1 ? String(localized: "\(status.searchable.formatted()) file indexed")
                : String(localized: "\(status.searchable.formatted()) files indexed")
            return indexed + (status.paused ? String(localized: " · paused") : "")
        }
    }

    /// While the model isn't there, how its download goes.
    private var downloadLine: String? {
        switch download.phase {
        case .ready: nil
        case .downloading: String(localized: "Downloading the model · \(Int(download.fraction * 100))%")
        case .verifying: String(localized: "Checking the model download…")
        case .retrying: String(localized: "Model download: waiting for the network")
        case .failed: String(localized: "⚠︎ The model download stopped")
        case .needed: status.pending > 0 ? String(localized: "The model isn't downloaded yet") : nil
        }
    }

    /// 0…1 for the menubar ring and progress bars: the model download, then an indexing pass or the rest of long files.
    var progress: Double? {
        if download.isActive { return download.fraction }
        switch status.activity {
        case .indexing(let done, let total) where total > 0: return Double(done) / Double(total)
        case .finishing(let done, let total, _) where total > 0: return Double(done) / Double(total)
        case .idle:
            guard let code = status.code.indexing, code.total > 0 else { return nil }
            return Double(code.done) / Double(code.total)
        default: return nil
        }
    }

    /// One line about the code index, for Settings → Code: "812 code files indexed", "Indexing code 42%…".
    var codeStatusLine: String {
        let code = status.code
        guard hasCode else { return String(localized: "Code search is off") }
        if !download.isReady { return String(localized: "Code is read once the model has downloaded") }
        if let indexing = code.indexing, indexing.total > 0 {
            let percent = Int((Double(indexing.done) / Double(indexing.total) * 100).rounded(.down))
            return String(localized: "Indexing code \(percent)% · \(indexing.done.formatted()) of \(indexing.total.formatted())")
        }
        let waiting = code.pending > 0 ? String(localized: " · \(code.pending.formatted()) waiting") : ""
        if code.pending > 0, status.paused { return String(localized: "Paused · \(code.pending.formatted()) code files waiting") }
        if code.pending > 0, let reason = status.waitingFor {
            return String(localized: "\(code.pending.formatted()) code files waiting · \(reason)")
        }
        if code.pending > 0, let until = status.heldUntil {
            let from = until.formatted(date: .omitted, time: .shortened)
            return String(localized: "\(code.pending.formatted()) code files waiting · indexing from \(from)")
        }
        // Code is read once the other folders have nothing waiting (the helper's order).
        if code.pending > 0, status.pending > 0 {
            return code.pending == 1
                ? String(localized: "\(code.pending.formatted()) code file waiting · read after your other files")
                : String(localized: "\(code.pending.formatted()) code files waiting · read after your other files")
        }
        let indexed = code.searchable == 1 ? String(localized: "\(code.searchable.formatted()) code file indexed")
            : String(localized: "\(code.searchable.formatted()) code files indexed")
        return indexed + waiting
    }

    /// A few words for the search bar while results may be incomplete: "Indexing 42%", "Downloading model · 42%".
    var activityBadge: String? {
        if download.isActive { return String(localized: "Downloading model · \(Int(download.fraction * 100))%") }
        if case .indexing(let done, let total) = status.activity, total > 0 {
            return String(localized: "Indexing \(Int(Double(done) / Double(total) * 100))%")
        }
        if status.paused, status.pending > 0 { return String(localized: "Indexing paused") }
        return nil
    }

    /// Why meaning search can't run yet (words still match), or nil.
    var meaningUnavailable: String? {
        guard !download.isReady else { return nil }
        if download.isActive {
            return String(localized: "Matching words only until the model has downloaded (\(Int(download.fraction * 100))%)")
        }
        return String(localized: "Matching words only: the model isn't downloaded")
    }

    /// Why results may be incomplete right now, or nil.
    var resultsCaveat: String? {
        if let meaningUnavailable { return meaningUnavailable }
        if case .indexing(let done, let total) = status.activity, total > 0 {
            return String(localized: "Still indexing (\(Int(Double(done) / Double(total) * 100))%): some files aren't in yet")
        }
        if status.pending > 0 {
            return status.pending == 1 ? String(localized: "\(status.pending.formatted()) file isn't indexed yet")
                : String(localized: "\(status.pending.formatted()) files aren't indexed yet")
        }
        return nil
    }
}
