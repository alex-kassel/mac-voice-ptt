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

final class EditableHistoryTextField: NSTextField {
    var onEditingBegan: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            self.textColor = .textColor
            if let editor = self.currentEditor() as? NSTextView {
                editor.textColor = .textColor
                editor.insertionPointColor = .textColor
            }
            onEditingBegan?()
        }
        return result
    }
}

final class HistoryRowCellView: NSTableCellView, NSTextFieldDelegate {
    let numLabel = NSTextField(labelWithString: "")
    let contentTextField = EditableHistoryTextField()
    let delBtn = NSButton()

    var onTextEdited: ((String) -> Void)?
    var onDeleteClicked: (() -> Void)?
    private var isCurrentlyEditing = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        // 1. Number label (#1, #2...)
        numLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12.0, weight: .bold)
        numLabel.textColor = .secondaryLabelColor
        numLabel.alignment = .left
        numLabel.isBezeled = false
        numLabel.drawsBackground = false
        numLabel.isEditable = false
        addSubview(numLabel)

        // 2. Editable Text field
        contentTextField.font = NSFont.systemFont(ofSize: 13.0)
        contentTextField.textColor = .labelColor
        contentTextField.isEditable = true
        contentTextField.isSelectable = true
        contentTextField.isBezeled = false
        contentTextField.drawsBackground = false
        contentTextField.cell?.wraps = true
        contentTextField.cell?.isScrollable = false
        contentTextField.delegate = self
        contentTextField.onEditingBegan = { [weak self] in
            self?.isCurrentlyEditing = true
        }
        addSubview(contentTextField)

        // 3. Delete button (✕)
        delBtn.title = "✕"
        delBtn.bezelStyle = .inline
        delBtn.isBordered = false
        delBtn.font = NSFont.systemFont(ofSize: 12.0, weight: .semibold)
        delBtn.target = self
        delBtn.action = #selector(deleteTapped)
        addSubview(delBtn)
    }

    @objc private func deleteTapped() {
        onDeleteClicked?()
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        isCurrentlyEditing = true
        contentTextField.textColor = .textColor
        if let editor = (obj.userInfo?["NSFieldEditor"] as? NSTextView)
            ?? contentTextField.currentEditor() as? NSTextView {
            editor.textColor = .textColor
            editor.insertionPointColor = .textColor
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        isCurrentlyEditing = false
        let isSelected = (superview as? NSTableRowView)?.isSelected ?? false
        updateAppearance(isSelected: isSelected)

        let newText = contentTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newText.isEmpty {
            onTextEdited?(newText)
        }
    }

    func configure(numText: String, text: String, isSelected: Bool) {
        numLabel.stringValue = numText
        contentTextField.stringValue = text
        updateLayout(isSelected: isSelected)
        updateAppearance(isSelected: isSelected)
    }

    func updateAppearance(isSelected: Bool) {
        if isCurrentlyEditing {
            contentTextField.textColor = .textColor
            numLabel.textColor = .secondaryLabelColor
            delBtn.contentTintColor = .secondaryLabelColor
            return
        }

        let isEmphasized = (superview as? NSTableRowView)?.isEmphasized ?? true

        if isSelected && isEmphasized {
            contentTextField.textColor = .white
            numLabel.textColor = NSColor(white: 0.9, alpha: 0.8)
            delBtn.contentTintColor = .white
        } else {
            contentTextField.textColor = .labelColor
            numLabel.textColor = .secondaryLabelColor
            delBtn.contentTintColor = .secondaryLabelColor
        }
    }

    func updateLayout(isSelected: Bool) {
        let h = bounds.height
        let numWidth: CGFloat = 34.0
        let delWidth: CGFloat = 24.0
        let textX: CGFloat = 46.0
        let textWidth = max(50.0, bounds.width - textX - delWidth - 12.0)

        if isSelected && h > 42.0 {
            // Expanded multi-line
            numLabel.frame = NSRect(x: 8, y: h - 26, width: numWidth, height: 18)
            delBtn.frame = NSRect(x: bounds.width - delWidth - 8, y: h - 26, width: delWidth, height: 18)
            contentTextField.frame = NSRect(x: textX, y: 10, width: textWidth, height: h - 20)
            contentTextField.maximumNumberOfLines = 0
            contentTextField.lineBreakMode = .byWordWrapping
        } else {
            // Collapsed single-line, perfectly vertically centered on the exact same baseline
            let midY = round((h - 20.0) / 2.0)
            numLabel.frame = NSRect(x: 8, y: midY, width: numWidth, height: 20)
            delBtn.frame = NSRect(x: bounds.width - delWidth - 8, y: midY, width: delWidth, height: 20)
            contentTextField.frame = NSRect(x: textX, y: midY, width: textWidth, height: 20)
            contentTextField.maximumNumberOfLines = 1
            contentTextField.lineBreakMode = .byTruncatingTail
        }
    }

    override func layout() {
        super.layout()
        let isSelected = (superview as? NSTableRowView)?.isSelected ?? false
        updateLayout(isSelected: isSelected)
        updateAppearance(isSelected: isSelected)
    }
}

final class HistoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    static let shared = HistoryWindowController()

    private var tableView: HistoryTableView!
    private var searchField: NSSearchField!
    private var countLabel: NSTextField!
    private var copyBtn: NSButton!
    private var deleteSelectedBtn: NSButton!
    private var copyFeedbackTimer: Timer?

    private var allItems: [String] = []
    private var filteredItems: [(index: Int, text: String)] = []

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Transcriptions History & Templates"
        window.minSize = NSSize(width: 500, height: 350)
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)

        setupUI()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResize(_:)),
            name: NSWindow.didResizeNotification,
            object: window
        )
    }

    @objc private func windowDidResize(_ notification: Notification) {
        if filteredItems.count > 0 {
            tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<filteredItems.count))
        }
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
        tableView.rowHeight = 38.0
        tableView.headerView = nil
        tableView.allowsMultipleSelection = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("TextColumn"))
        col.resizingMask = .autoresizingMask
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
        copyBtn.frame = NSRect(x: bounds.width - 250, y: 14, width: 155, height: 28)
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

        let focusMode = ConfigManager.shared.config.focusMode

        if let window = self.window {
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            switch focusMode {
            case .firstItem:
                if filteredItems.count > 0 {
                    tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                    tableView.scrollRowToVisible(0)
                    window.makeFirstResponder(tableView)
                }
            case .searchField:
                tableView.deselectAll(nil)
                window.makeFirstResponder(searchField)
            }
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

        countLabel.stringValue = "\(filteredItems.count) of \(allItems.count) items • Click to expand full text, edit inline, Cmd+Click to combine"
        tableView.reloadData()
        updateSelectionUI()
    }

    func controlTextDidChange(_ obj: Notification) {
        if (obj.object as? NSSearchField) == searchField {
            applyFilter()
        }
    }

    // MARK: - NSTableViewDataSource & Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        return filteredItems.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row < filteredItems.count else { return 38.0 }
        let isSelected = tableView.isRowSelected(row)
        if !isSelected {
            return 38.0
        }

        // Calculate dynamic height for expanded full text
        let text = filteredItems[row].text
        let font = NSFont.systemFont(ofSize: 13.0)
        let availableWidth = max(100.0, tableView.bounds.width - 98.0)
        let constraintRect = CGSize(width: availableWidth, height: .greatestFiniteMagnitude)
        let boundingBox = (text as NSString).boundingRect(
            with: constraintRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        let textHeight = ceil(boundingBox.height)
        return min(400.0, max(38.0, textHeight + 22.0))
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filteredItems.count else { return nil }
        let item = filteredItems[row]
        let isSelected = tableView.isRowSelected(row)

        let identifier = NSUserInterfaceItemIdentifier("HistoryRowCellView")
        var cell = tableView.makeView(withIdentifier: identifier, owner: self) as? HistoryRowCellView
        if cell == nil {
            cell = HistoryRowCellView(frame: NSRect(x: 0, y: 0, width: tableView.bounds.width, height: 38))
            cell?.identifier = identifier
        }

        cell?.configure(
            numText: "#\(item.index + 1)",
            text: item.text,
            isSelected: isSelected
        )

        cell?.onTextEdited = { [weak self] newText in
            guard let self = self else { return }
            HistoryManager.shared.update(index: item.index, newText: newText)
            self.refreshData()
        }

        cell?.onDeleteClicked = { [weak self] in
            guard let self = self else { return }
            self.confirmAndDelete(index: item.index, text: item.text)
        }

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateSelectionUI()

        let count = filteredItems.count
        guard count > 0 else { return }

        // Animate row height transitions: selected rows expand to full text, unselected collapse to single line
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0.15
        tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<count))
        NSAnimationContext.endGrouping()
    }

    private func updateSelectionUI() {
        let count = tableView.selectedRowIndexes.count
        deleteSelectedBtn.isEnabled = count > 0
        copyBtn.isEnabled = count > 0

        // If currently showing copy feedback animation, don't overwrite the title
        guard copyFeedbackTimer == nil else { return }

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

    private func showCopySuccessFeedback(count: Int) {
        copyFeedbackTimer?.invalidate()

        let successTitle = count > 1 ? "✓ Copied (\(count))!" : "✓ Copied!"
        copyBtn.title = successTitle
        if #available(macOS 11.0, *) {
            copyBtn.contentTintColor = .systemGreen
        }

        // Tactile haptic feedback on supported trackpads
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)

        copyFeedbackTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.copyFeedbackTimer = nil
            if #available(macOS 11.0, *) {
                self.copyBtn.contentTintColor = nil
            }
            self.updateSelectionUI()
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

        let copied: Bool
        if originalIndexes.count == 1 {
            copied = HistoryManager.shared.copyToClipboard(index: originalIndexes[0])
        } else {
            copied = HistoryManager.shared.copyCombined(indexes: originalIndexes, separator: "\n") != nil
        }

        if copied {
            showCopySuccessFeedback(count: originalIndexes.count)
        }
    }

    private func confirmAndDelete(index: Int, text: String) {
        guard let window = self.window else { return }
        let preview = text.count > 60 ? String(text.prefix(60)) + "..." : text
        let alert = NSAlert()
        alert.messageText = "Delete Transcription?"
        alert.informativeText = "Are you sure you want to delete this transcription?\n\n\"\(preview)\""
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                HistoryManager.shared.delete(index: index)
                self?.refreshData()
            }
        }
    }

    @objc private func deleteSelectedClicked() {
        let selectedRows = tableView.selectedRowIndexes
        guard !selectedRows.isEmpty, let window = self.window else { return }

        var originalIndexes: [Int] = []
        for r in selectedRows {
            if r < filteredItems.count {
                originalIndexes.append(filteredItems[r].index)
            }
        }

        let count = originalIndexes.count
        let alert = NSAlert()
        alert.messageText = count == 1 ? "Delete Selected Item?" : "Delete \(count) Selected Items?"
        alert.informativeText = count == 1
            ? "Are you sure you want to delete the selected transcription?"
            : "Are you sure you want to delete \(count) selected transcriptions?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                HistoryManager.shared.delete(indexes: originalIndexes)
                self?.refreshData()
            }
        }
    }

    @objc private func clearAllClicked() {
        guard let window = self.window else { return }
        let alert = NSAlert()
        alert.messageText = "Clear Transcriptions History"
        alert.informativeText = "Are you sure you want to delete all saved transcriptions? This action cannot be undone."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Clear All")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                HistoryManager.shared.clear()
                self?.refreshData()
            }
        }
    }

    @objc private func closeClicked() {
        window?.close()
    }
}
