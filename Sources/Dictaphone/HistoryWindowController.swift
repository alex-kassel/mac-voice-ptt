import Foundation
import AppKit

final class HistoryTableView: NSTableView {
    var onDeleteKeyPressed: (() -> Void)?
    var onCopyKeyPressed: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { // Delete / Backspace
            onDeleteKeyPressed?()
        } else if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" {
            onCopyKeyPressed?()
        } else {
            super.keyDown(with: event)
        }
    }
}

final class HistoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSTextFieldDelegate {
    static let shared = HistoryWindowController()

    private var tableView: HistoryTableView!
    private var searchField: NSSearchField!
    private var countLabel: NSTextField!
    private var copyBtn: NSButton!
    private var deleteSelectedBtn: NSButton!

    private var allItems: [String] = []
    private var filteredItems: [(index: Int, text: String)] = []

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Transcriptions History & Templates"
        window.minSize = NSSize(width: 480, height: 340)
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

        // 1. Top Bar: Search Field & Instruction Label
        searchField = NSSearchField(frame: NSRect(x: 20, y: bounds.height - 44, width: 300, height: 26))
        searchField.placeholderString = "Search or filter transcriptions..."
        searchField.delegate = self
        searchField.autoresizingMask = [.maxXMargin, .minYMargin]
        contentView.addSubview(searchField)

        countLabel = NSTextField(labelWithString: "0 items")
        countLabel.frame = NSRect(x: 330, y: bounds.height - 40, width: bounds.width - 350, height: 20)
        countLabel.font = NSFont.systemFont(ofSize: 12.0)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right
        countLabel.autoresizingMask = [.width, .minYMargin]
        contentView.addSubview(countLabel)

        // 2. Scrollable Table View with Multiple Selection
        let scrollY: CGFloat = 56.0
        let scrollHeight = bounds.height - 56.0 - 52.0
        let scrollView = NSScrollView(frame: NSRect(x: 20, y: scrollY, width: bounds.width - 40, height: scrollHeight))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder

        tableView = HistoryTableView(frame: scrollView.bounds)
        tableView.autoresizingMask = [.width, .height]
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 48.0
        tableView.headerView = nil
        tableView.allowsMultipleSelection = true

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("TextColumn"))
        col.width = scrollView.bounds.width - 24.0
        tableView.addTableColumn(col)

        tableView.dataSource = self
        tableView.delegate = self

        tableView.onDeleteKeyPressed = { [weak self] in
            self?.deleteSelectedClicked()
        }
        tableView.onCopyKeyPressed = { [weak self] in
            self?.copySelectedClicked()
        }

        scrollView.documentView = tableView
        contentView.addSubview(scrollView)

        // 3. Bottom Bar: Actions & Buttons
        let clearBtn = NSButton(title: "Clear All", target: self, action: #selector(clearAllClicked))
        clearBtn.frame = NSRect(x: 20, y: 14, width: 85, height: 28)
        clearBtn.bezelStyle = .rounded
        clearBtn.autoresizingMask = [.maxXMargin, .maxYMargin]
        contentView.addSubview(clearBtn)

        deleteSelectedBtn = NSButton(title: "Delete", target: self, action: #selector(deleteSelectedClicked))
        deleteSelectedBtn.frame = NSRect(x: 110, y: 14, width: 80, height: 28)
        deleteSelectedBtn.bezelStyle = .rounded
        deleteSelectedBtn.isEnabled = false
        deleteSelectedBtn.autoresizingMask = [.maxXMargin, .maxYMargin]
        contentView.addSubview(deleteSelectedBtn)

        copyBtn = NSButton(title: "Copy to Clipboard", target: self, action: #selector(copySelectedClicked))
        copyBtn.frame = NSRect(x: bounds.width - 240, y: 14, width: 145, height: 28)
        copyBtn.bezelStyle = .rounded
        copyBtn.isEnabled = false
        copyBtn.autoresizingMask = [.minXMargin, .maxYMargin]
        contentView.addSubview(copyBtn)

        let closeBtn = NSButton(title: "Close", target: self, action: #selector(closeClicked))
        closeBtn.frame = NSRect(x: bounds.width - 90, y: 14, width: 70, height: 28)
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
            filteredItems = allItems.enumerated().map { ($0.offset, $0.element) }
        } else {
            filteredItems = allItems.enumerated()
                .filter { $0.element.lowercased().contains(query) }
                .map { ($0.offset, $0.element) }
        }

        countLabel.stringValue = "\(filteredItems.count) of \(allItems.count) items • Double-click/Enter to edit, Cmd+Click to multi-select"
        tableView.reloadData()
        updateSelectionUI()
    }

    func controlTextDidChange(_ obj: Notification) {
        if (obj.object as? NSSearchField) == searchField {
            applyFilter()
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField, textField.tag >= 1000 else { return }
        let originalIndex = textField.tag - 1000
        let newText = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newText.isEmpty {
            HistoryManager.shared.update(index: originalIndex, newText: newText)
            refreshData()
        }
    }

    // MARK: - NSTableViewDataSource & Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        return filteredItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filteredItems.count else { return nil }
        let item = filteredItems[row]

        let identifier = NSUserInterfaceItemIdentifier("EditableHistoryCell")
        var cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
        if cell == nil {
            cell = NSTableCellView(frame: NSRect(x: 0, y: 0, width: tableView.bounds.width, height: 48))
            cell?.identifier = identifier

            // Number label
            let numLabel = NSTextField(labelWithString: "")
            numLabel.tag = 100
            numLabel.frame = NSRect(x: 8, y: 14, width: 36, height: 20)
            numLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12.0, weight: .bold)
            numLabel.textColor = .secondaryLabelColor
            cell?.addSubview(numLabel)

            // Editable Text Field
            let textField = NSTextField(frame: NSRect(x: 48, y: 6, width: tableView.bounds.width - 92, height: 36))
            textField.tag = 101
            textField.font = NSFont.systemFont(ofSize: 13.0)
            textField.textColor = .labelColor
            textField.isEditable = true
            textField.isSelectable = true
            textField.isBezeled = false
            textField.drawsBackground = false
            textField.maximumNumberOfLines = 2
            textField.lineBreakMode = .byTruncatingTail
            textField.delegate = self
            textField.autoresizingMask = [.width]
            cell?.addSubview(textField)

            // Delete row button (✕)
            let delBtn = NSButton(title: "✕", target: self, action: #selector(deleteRowButtonClicked(_:)))
            delBtn.tag = 102
            delBtn.frame = NSRect(x: tableView.bounds.width - 38, y: 12, width: 26, height: 24)
            delBtn.bezelStyle = .inline
            delBtn.isBordered = false
            delBtn.font = NSFont.systemFont(ofSize: 12.0, weight: .semibold)
            delBtn.autoresizingMask = [.minXMargin]
            cell?.addSubview(delBtn)
        }

        if let num = cell?.viewWithTag(100) as? NSTextField {
            num.stringValue = "#\(item.index + 1)"
        }
        if let tf = cell?.viewWithTag(101) as? NSTextField {
            tf.stringValue = item.text
            tf.tag = 1000 + item.index // store original index for editing
        }
        if let btn = cell?.viewWithTag(102) as? NSButton {
            btn.identifier = NSUserInterfaceItemIdentifier("\(item.index)")
        }

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateSelectionUI()
    }

    private func updateSelectionUI() {
        let count = tableView.selectedRowIndexes.count
        deleteSelectedBtn.isEnabled = count > 0
        copyBtn.isEnabled = count > 0

        if count == 0 {
            copyBtn.title = "Copy to Clipboard"
            deleteSelectedBtn.title = "Delete"
        } else if count == 1 {
            copyBtn.title = "Copy Selected"
            deleteSelectedBtn.title = "Delete (1)"
        } else {
            copyBtn.title = "Copy Combined (\(count))"
            deleteSelectedBtn.title = "Delete (\(count))"
        }
    }

    @objc private func copySelectedClicked() {
        let selectedRows = tableView.selectedRowIndexes
        guard !selectedRows.isEmpty else { return }

        var originalIndexes: [Int] = []
        for r in selectedRows {
            if r < filteredItems.count {
                originalIndexes.append(filteredItems[r].index)
            }
        }

        if originalIndexes.count == 1 {
            _ = HistoryManager.shared.copyToClipboard(index: originalIndexes[0])
        } else {
            _ = HistoryManager.shared.copyCombined(indexes: originalIndexes, separator: " ")
        }
    }

    @objc private func deleteSelectedClicked() {
        let selectedRows = tableView.selectedRowIndexes
        guard !selectedRows.isEmpty else { return }

        var originalIndexes: [Int] = []
        for r in selectedRows {
            if r < filteredItems.count {
                originalIndexes.append(filteredItems[r].index)
            }
        }

        HistoryManager.shared.delete(indexes: originalIndexes)
        refreshData()
    }

    @objc private func deleteRowButtonClicked(_ sender: NSButton) {
        guard let idStr = sender.identifier?.rawValue, let originalIndex = Int(idStr) else { return }
        HistoryManager.shared.delete(index: originalIndex)
        refreshData()
    }

    @objc private func clearAllClicked() {
        let alert = NSAlert()
        alert.messageText = "Clear Transcriptions History"
        alert.informativeText = "Are you sure you want to delete all saved transcriptions?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear All")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            HistoryManager.shared.clear()
            refreshData()
        }
    }

    @objc private func closeClicked() {
        window?.close()
    }
}
