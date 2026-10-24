import Foundation
import AppKit

final class HistoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    static let shared = HistoryWindowController()

    private var tableView: NSTableView!
    private var searchField: NSSearchField!
    private var countLabel: NSTextField!
    private var allItems: [String] = []
    private var filteredItems: [String] = []

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Recent Transcriptions"
        window.minSize = NSSize(width: 440, height: 320)
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)

        setupUI()
    }

    private func setupUI() {
        guard let window = self.window else { return }
        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView

        let bounds = contentView.bounds

        // 1. Top Bar: Search Field & Count Label
        searchField = NSSearchField(frame: NSRect(x: 20, y: bounds.height - 44, width: 320, height: 26))
        searchField.placeholderString = "Search transcriptions..."
        searchField.delegate = self
        searchField.autoresizingMask = [.maxXMargin, .minYMargin]
        contentView.addSubview(searchField)

        countLabel = NSTextField(labelWithString: "0 items")
        countLabel.frame = NSRect(x: 350, y: bounds.height - 40, width: 190, height: 20)
        countLabel.font = NSFont.systemFont(ofSize: 12.0)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right
        countLabel.autoresizingMask = [.minXMargin, .minYMargin]
        contentView.addSubview(countLabel)

        // 2. Scrollable Table View
        let scrollY: CGFloat = 56.0
        let scrollHeight = bounds.height - 56.0 - 52.0
        let scrollView = NSScrollView(frame: NSRect(x: 20, y: scrollY, width: bounds.width - 40, height: scrollHeight))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder

        tableView = NSTableView(frame: scrollView.bounds)
        tableView.autoresizingMask = [.width, .height]
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 44.0
        tableView.headerView = nil
        tableView.doubleAction = #selector(tableDoubleClicked)
        tableView.target = self

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("TextColumn"))
        col.width = scrollView.bounds.width - 24.0
        tableView.addTableColumn(col)

        tableView.dataSource = self
        tableView.delegate = self
        scrollView.documentView = tableView
        contentView.addSubview(scrollView)

        // 3. Bottom Bar Buttons
        let clearBtn = NSButton(title: "Clear History", target: self, action: #selector(clearClicked))
        clearBtn.frame = NSRect(x: 20, y: 14, width: 110, height: 28)
        clearBtn.bezelStyle = .rounded
        clearBtn.autoresizingMask = [.maxXMargin, .maxYMargin]
        contentView.addSubview(clearBtn)

        let copyBtn = NSButton(title: "Copy Selected", target: self, action: #selector(copySelectedClicked))
        copyBtn.frame = NSRect(x: bounds.width - 240, y: 14, width: 120, height: 28)
        copyBtn.bezelStyle = .rounded
        copyBtn.autoresizingMask = [.minXMargin, .maxYMargin]
        contentView.addSubview(copyBtn)

        let closeBtn = NSButton(title: "Close", target: self, action: #selector(closeClicked))
        closeBtn.frame = NSRect(x: bounds.width - 110, y: 14, width: 90, height: 28)
        closeBtn.bezelStyle = .rounded
        closeBtn.keyEquivalent = "\r"
        closeBtn.autoresizingMask = [.minXMargin, .maxYMargin]
        contentView.addSubview(closeBtn)
    }

    func showHistory() {
        refreshData()
        if let window = self.window {
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func refreshData() {
        allItems = HistoryManager.shared.getHistory()
        applyFilter()
    }

    private func applyFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            filteredItems = allItems
        } else {
            filteredItems = allItems.filter { $0.lowercased().contains(query) }
        }

        countLabel.stringValue = "\(filteredItems.count) of \(allItems.count) stored"
        tableView.reloadData()
    }

    func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }

    // MARK: - NSTableViewDataSource & Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        return filteredItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filteredItems.count else { return nil }
        let text = filteredItems[row]

        let identifier = NSUserInterfaceItemIdentifier("HistoryCell")
        var cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
        if cell == nil {
            cell = NSTableCellView(frame: NSRect(x: 0, y: 0, width: tableView.bounds.width, height: 44))
            cell?.identifier = identifier

            let numLabel = NSTextField(labelWithString: "")
            numLabel.tag = 100
            numLabel.frame = NSRect(x: 8, y: 12, width: 36, height: 20)
            numLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12.0, weight: .bold)
            numLabel.textColor = .secondaryLabelColor
            cell?.addSubview(numLabel)

            let textLabel = NSTextField(labelWithString: "")
            textLabel.tag = 101
            textLabel.frame = NSRect(x: 48, y: 4, width: tableView.bounds.width - 60, height: 36)
            textLabel.font = NSFont.systemFont(ofSize: 12.5)
            textLabel.textColor = .labelColor
            textLabel.maximumNumberOfLines = 2
            textLabel.lineBreakMode = .byTruncatingTail
            textLabel.autoresizingMask = [.width]
            cell?.addSubview(textLabel)
        }

        if let num = cell?.viewWithTag(100) as? NSTextField {
            num.stringValue = "#\(row + 1)"
        }
        if let lbl = cell?.viewWithTag(101) as? NSTextField {
            lbl.stringValue = text
        }

        return cell
    }

    @objc private func tableDoubleClicked() {
        copySelectedClicked()
    }

    @objc private func copySelectedClicked() {
        let row = tableView.selectedRow
        guard row >= 0 && row < filteredItems.count else { return }
        let text = filteredItems[row]

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        Logger.log("[HistoryWindow] Copied transcription to clipboard (%ld chars)", text.count)
    }

    @objc private func clearClicked() {
        HistoryManager.shared.clear()
        refreshData()
    }

    @objc private func closeClicked() {
        window?.close()
    }
}
