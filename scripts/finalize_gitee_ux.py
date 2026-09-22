from pathlib import Path
p=Path('DynamicIsland/ToolIsleFeatures/Gitee/GIUXProbe.swift')
s=p.read_text();old='            func snapshot(_ stage: String) {'
assert s.count(old)==1
p.write_text(s.replace(old,'            @MainActor func snapshot(_ stage: String) {'))
p=Path('DynamicIsland/ToolIsleFeatures/Gitee/GIReaderSession.swift')
s=p.read_text();old='        applyPolicy(isOpen || otherDocument ? .regular : .accessory)'
new='''        let requiresForeground = isOpen || otherDocument
        applyPolicy(requiresForeground ? .regular : .accessory)
        // Preserve Atoll's original last-window handoff without deactivating
        // an open (including minimized or hidden) reader or another document.
        if !requiresForeground && NSApp.isActive { NSApp.deactivate() }'''
assert s.count(old)==1
p.write_text(s.replace(old,new))
