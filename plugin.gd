@tool
extends EditorPlugin

# Original source by Ryhon0: https://github.com/Ryhon0/ModZipExporter
# Additional tweaks by sturnclaw: https://github.com/Ryhon0/ModZipExporter/pull/5
# Export options, blacklists, vmz support, disabled explorer window, UI redesign, QoL features by Romero: https://github.com/Apex-Artifex/VostokModExporter

const DEFAULT_EXT_BLACKLIST: String = "md|psd|blend|kra|tmp|log|zip|rar|7z"
const DEFAULT_NAME_BLACKLIST: String = ".git|.github|.vscode|.idea|.cache|docs|tests|build|dist|out|temp|backup|examples|screenshots"

var dock: EditorDock
var dockBtn : Button
var projectSelect: OptionButton
var dirline: LineEdit
var fileline: LineEdit
var progressBar: ProgressBar
var progressLabel: Label
var currentLabel: Label
var detectedProjects: Array[String]
var compiledRemaps: Dictionary
var exportTextTimer: SceneTreeTimer
var stripUidCheckbox: CheckBox
var remapCheckbox: CheckBox
var remapAssetsCheckbox: CheckBox
var forceRemapsCheckbox: CheckBox
var includeGlobalScriptClassCacheCheckbox: CheckBox
var extBlacklistLine: LineEdit
var nameBlacklistLine: LineEdit
var exactNameMatchCheckbox: CheckBox

var _uid_attr_regex: RegEx = RegEx.new()
var _uid_any_regex: RegEx = RegEx.new()

var output_dir_setting: String = "vostok_mod_exporter/output_path"
var version_setting: String = "vostok_mod_exporter/include_version_in_filename"
var options_expanded_setting: String = "vostok_mod_exporter/options_expanded"
var blacklist_expanded_setting: String = "vostok_mod_exporter/blacklist_expanded"

var ext_blacklist_setting: String = "vostok_mod_exporter/ext_blacklist"
var name_blacklist_setting: String = "vostok_mod_exporter/name_blacklist"
var exact_match_setting: String = "vostok_mod_exporter/exact_match"

var _extBlacklist: PackedStringArray
var _nameBlacklist: PackedStringArray
var _exactMatch: bool

func _build_default_filename(mod_path: String):
    var filename = mod_path.get_file()
    
    if EditorInterface.get_editor_settings().get_setting(version_setting):
    
        var modCfg: ConfigFile = ConfigFile.new()
        modCfg.load(mod_path.path_join("mod.txt"))
        
        var version = modCfg.get_value("mod", "version")
        if version: filename += "-" + version
    
    return filename + ".vmz"

func _enter_tree() -> void:
    dock = EditorDock.new()
    dock.default_slot = EditorDock.DOCK_SLOT_LEFT_BR
    dock.size_flags_vertical = Control.SIZE_SHRINK_END
    dock.title = "Vostok Mod Exporter"
    
    var container = VBoxContainer.new()
    dock.add_child(container)
    
    var header = Label.new()
    header.text = "Select mod folder to export:"
    header.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    container.add_child(header)
    
    var inputBox = HBoxContainer.new()
    container.add_child(inputBox)
    
    var projectScanBtn = Button.new()
    projectScanBtn.text = "Scan"
    projectScanBtn.pressed.connect(func(): scanProjects())
    inputBox.add_child(projectScanBtn)

    projectSelect = OptionButton.new()
    projectSelect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    projectSelect.item_selected.connect(func(index: int):
        dirline.text = detectedProjects[index]
        fileline.text = _build_default_filename(detectedProjects[index])
        )
    inputBox.add_child(projectSelect)

    var fileDialogBtn = Button.new()
    fileDialogBtn.text = "..."
    fileDialogBtn.pressed.connect(func(): 
        var fd := FileDialog.new()
        fd.size = Vector2(700,400)
        fd.title = "Select mod folder"
        fd.file_mode = FileDialog.FILE_MODE_OPEN_DIR
        fd.access = FileDialog.ACCESS_RESOURCES
        fd.dir_selected.connect(func(dir): dirline.text = dir)
        fd.canceled.connect(func(): fd.queue_free())
        fd.close_requested.connect(func(): fd.queue_free())
        
        add_child(fd)
        fd.popup_centered()
        )
    inputBox.add_child(fileDialogBtn)

    dirline = LineEdit.new()
    dirline.placeholder_text = "res://mods/MyMod"
    dirline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    container.add_child(dirline)
    
    container.add_child(HSeparator.new())
    
    var outputHeader = Label.new()
    outputHeader.text = "Output:"
    outputHeader.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    container.add_child(outputHeader)
    
    var fileBox = HBoxContainer.new()
    fileBox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    container.add_child(fileBox)

    fileline = LineEdit.new()
    fileline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    fileline.placeholder_text = "mod.vmz"
    fileline.custom_minimum_size = Vector2(200, 0)
    fileline.expand_to_text_length = true
    fileBox.add_child(fileline)

    var outputDirBtn = Button.new()
    outputDirBtn.text = "..."
    outputDirBtn.pressed.connect(func():
        var fd := FileDialog.new()
        fd.size = Vector2(700, 400)
        fd.title = "Select output folder"
        fd.file_mode = FileDialog.FILE_MODE_OPEN_DIR
        fd.access = FileDialog.ACCESS_FILESYSTEM
        
        var path = EditorInterface.get_editor_settings().get_setting(output_dir_setting)
        fd.current_dir = path if path && !path.is_empty() else ProjectSettings.globalize_path("res://")
        
        fd.dir_selected.connect(func(dir):
            EditorInterface.get_editor_settings().set_setting(output_dir_setting, dir)
        )
        fd.canceled.connect(func(): fd.queue_free())
        fd.close_requested.connect(func(): fd.queue_free())
        
        add_child(fd)
        fd.popup_centered()
        )
    fileBox.add_child(outputDirBtn)

    container.add_child(HSeparator.new())

    # OPTIONS

    var optionsHeaderBtn = Button.new()
    optionsHeaderBtn.text = "▶ Options"
    optionsHeaderBtn.toggle_mode = true
    optionsHeaderBtn.button_pressed = false
    optionsHeaderBtn.alignment = HORIZONTAL_ALIGNMENT_LEFT
    container.add_child(optionsHeaderBtn)

    var optionsBox = VBoxContainer.new()
    optionsBox.visible = false
    optionsBox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    optionsBox.add_theme_constant_override("separation", 6)

    var optionsExpanded = EditorInterface.get_editor_settings().get_setting(options_expanded_setting)
    if optionsExpanded == null: optionsExpanded = false

    optionsHeaderBtn.button_pressed = optionsExpanded
    optionsHeaderBtn.text = ("▼ " if optionsExpanded else "▶ ") + "Options"
    optionsBox.visible = optionsExpanded

    optionsHeaderBtn.toggled.connect(func(pressed: bool):
        optionsBox.visible = pressed
        optionsHeaderBtn.text = ("▼ " if pressed else "▶ ") + "Options"
        EditorInterface.get_editor_settings().set_setting(options_expanded_setting, pressed)
    )

    var optionsMargin = MarginContainer.new()
    optionsMargin.add_theme_constant_override("margin_left", 12)
    optionsMargin.add_child(optionsBox)
    container.add_child(optionsMargin)

    stripUidCheckbox = CheckBox.new()
    stripUidCheckbox.text = "Remove uid from ext_resource"
    stripUidCheckbox.button_pressed = true
    optionsBox.add_child(stripUidCheckbox)

    remapCheckbox = CheckBox.new()
    remapCheckbox.text = "Remap `.tres` & `.tscn` files"
    remapCheckbox.button_pressed = false
    optionsBox.add_child(remapCheckbox)

    remapAssetsCheckbox = CheckBox.new()
    remapAssetsCheckbox.text = "Remap assets (.import)"
    remapAssetsCheckbox.button_pressed = true
    optionsBox.add_child(remapAssetsCheckbox)

    includeGlobalScriptClassCacheCheckbox = CheckBox.new()
    includeGlobalScriptClassCacheCheckbox.text = "Include global script class cache"
    includeGlobalScriptClassCacheCheckbox.button_pressed = true
    optionsBox.add_child(includeGlobalScriptClassCacheCheckbox)

    forceRemapsCheckbox = CheckBox.new()
    forceRemapsCheckbox.text = "Force [remaps] section"
    forceRemapsCheckbox.button_pressed = true
    optionsBox.add_child(forceRemapsCheckbox)

    optionsBox.add_child(HSeparator.new())

    # if not remapCheckbox.toggled.is_connected(_update_force_remaps_checkbox_state):
    #     remapCheckbox.toggled.connect(_update_force_remaps_checkbox_state)

    if not stripUidCheckbox.toggled.is_connected(_on_strip_uid_checkbox_toggled):
        stripUidCheckbox.toggled.connect(_on_strip_uid_checkbox_toggled)
    _on_strip_uid_checkbox_toggled(stripUidCheckbox.button_pressed)

    # BLACKLIST SETTINGS

    var blacklistHeaderBtn = Button.new()
    blacklistHeaderBtn.text = "▶ Blacklist Settings"
    blacklistHeaderBtn.toggle_mode = true
    blacklistHeaderBtn.button_pressed = false
    blacklistHeaderBtn.alignment = HORIZONTAL_ALIGNMENT_LEFT
    container.add_child(blacklistHeaderBtn)

    var blacklistBox = VBoxContainer.new()
    blacklistBox.visible = false
    blacklistBox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    blacklistBox.add_theme_constant_override("separation", 6)

    var blacklistExpanded = EditorInterface.get_editor_settings().get_setting(blacklist_expanded_setting)
    if blacklistExpanded == null: blacklistExpanded = false

    blacklistHeaderBtn.button_pressed = blacklistExpanded
    blacklistHeaderBtn.text = ("▼ " if blacklistExpanded else "▶ ") + "Blacklist Settings"
    blacklistBox.visible = blacklistExpanded

    blacklistHeaderBtn.toggled.connect(func(pressed: bool):
        blacklistBox.visible = pressed
        blacklistHeaderBtn.text = ("▼ " if pressed else "▶ ") + "Blacklist Settings"
        EditorInterface.get_editor_settings().set_setting(blacklist_expanded_setting, pressed)
    )

    var blacklistMargin = MarginContainer.new()
    blacklistMargin.add_theme_constant_override("margin_left", 12)
    blacklistMargin.add_child(blacklistBox)
    container.add_child(blacklistMargin)

    var extLabel = Label.new()
    extLabel.text = "Extensions blacklist (| separated)"
    blacklistBox.add_child(extLabel)

    extBlacklistLine = LineEdit.new()
    extBlacklistLine.placeholder_text = DEFAULT_EXT_BLACKLIST
    blacklistBox.add_child(extBlacklistLine)

    var nameLabel = Label.new()
    nameLabel.text = "Names blacklist (files & folders, | separated)"
    blacklistBox.add_child(nameLabel)

    nameBlacklistLine = LineEdit.new()
    nameBlacklistLine.placeholder_text = DEFAULT_NAME_BLACKLIST
    blacklistBox.add_child(nameBlacklistLine)

    exactNameMatchCheckbox = CheckBox.new()
    exactNameMatchCheckbox.text = "Exact blacklist name match"
    exactNameMatchCheckbox.button_pressed = true
    blacklistBox.add_child(exactNameMatchCheckbox)

    var resetBlacklistsBtn = Button.new()
    resetBlacklistsBtn.text = "Reset to defaults"
    resetBlacklistsBtn.pressed.connect(func():
        extBlacklistLine.text = DEFAULT_EXT_BLACKLIST
        nameBlacklistLine.text = DEFAULT_NAME_BLACKLIST
        exactNameMatchCheckbox.button_pressed = true
    )
    blacklistBox.add_child(resetBlacklistsBtn)

    blacklistBox.add_child(HSeparator.new())

    # Load saved blacklists or fallback to defaults

    var savedExt = EditorInterface.get_editor_settings().get_setting(ext_blacklist_setting)
    var savedName = EditorInterface.get_editor_settings().get_setting(name_blacklist_setting)
    var savedExact = EditorInterface.get_editor_settings().get_setting(exact_match_setting)

    extBlacklistLine.text = savedExt if savedExt != null and not savedExt.is_empty() else DEFAULT_EXT_BLACKLIST
    nameBlacklistLine.text = savedName if savedName != null and not savedName.is_empty() else DEFAULT_NAME_BLACKLIST
    exactNameMatchCheckbox.button_pressed = savedExact if savedExact != null else true

    extBlacklistLine.text_changed.connect(func(t):
        EditorInterface.get_editor_settings().set_setting(ext_blacklist_setting, t)
    )

    nameBlacklistLine.text_changed.connect(func(t):
        EditorInterface.get_editor_settings().set_setting(name_blacklist_setting, t)
    )

    exactNameMatchCheckbox.toggled.connect(func(v):
        EditorInterface.get_editor_settings().set_setting(exact_match_setting, v)
    )

    container.add_child(HSeparator.new())

    # EXPORT

    var marginBox = MarginContainer.new()
    marginBox.add_theme_constant_override("margin_top", 0)
    marginBox.add_theme_constant_override("margin_bottom", 6)
    marginBox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    container.add_child(marginBox)
    
    var exportBox = HBoxContainer.new()
    exportBox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    marginBox.add_child(exportBox)
    
    var btn = Button.new()
    btn.text = "Export!"
    btn.custom_minimum_size = Vector2(100, 0)
    btn.pressed.connect(exportZip)
    exportBox.add_child(btn)
    
    progressBar = ProgressBar.new()
    progressBar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    progressBar.size_flags_vertical = Control.SIZE_EXPAND_FILL
    exportBox.add_child(progressBar)
    
    var progressBox = HBoxContainer.new()
    container.add_child(progressBox)

    progressLabel = Label.new()
    progressLabel.visible = false
    progressBox.add_child(progressLabel)

    currentLabel = Label.new()
    currentLabel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    currentLabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    currentLabel.visible = false
    progressBox.add_child(currentLabel)
    
    scanProjects()
    
    add_dock(dock)

# func _update_force_remaps_checkbox_state(toggled_on: bool) -> void:
#     forceRemapsCheckbox.disabled = toggled_on

func _on_strip_uid_checkbox_toggled(toggled_on: bool) -> void:
    if stripUidCheckbox.button_pressed:
        remapCheckbox.button_pressed = false
    remapCheckbox.disabled = toggled_on

func _exit_tree():
    remove_dock(dock)
    dock.queue_free()

func scanProjects():
    projectSelect.clear()
    detectedProjects.clear()

    scanDirForProjects("res://")

    if projectSelect.item_count > 0:
        projectSelect.item_selected.emit(0)
    
func scanDirForProjects(dir):
    for d in DirAccess.get_directories_at(dir):
        if FileAccess.file_exists(dir.path_join(d).path_join("mod.txt")):
            detectedProjects.append(dir.path_join(d))
            projectSelect.add_item(d)
        else:
            scanDirForProjects(dir.path_join(d))

var zipPaths = []
var customResourceHash = ""
var files: Array[String] = []
func exportZip():
    var forceRemaps: bool = forceRemapsCheckbox.button_pressed
    var includeGlobalScriptClassCache: bool = includeGlobalScriptClassCacheCheckbox.button_pressed

    _extBlacklist = _parse_blacklist(extBlacklistLine.text)
    _nameBlacklist = _parse_blacklist(nameBlacklistLine.text)
    _exactMatch = exactNameMatchCheckbox.button_pressed

    currentLabel.modulate = Color.WHITE
    compiledRemaps = {}

    var dir = dirline.text
    var out = fileline.text

    var modCfgPath = null
    var overrideCfgPath = dir.path_join("override.cfg")
    if FileAccess.file_exists(dir.path_join("mod.txt")):
        modCfgPath = dir.path_join("mod.txt")
        
    var outDir = EditorInterface.get_editor_settings().get_setting(output_dir_setting)
    if !outDir || outDir.is_empty():
        outDir = "res://mods/"

    DirAccess.make_dir_absolute(outDir)

    customResourceHash = DirAccess.get_directories_at("res://.godot/exported")[0]
    files = []
    collectFiles(dir)

    zipPaths = []
    var zip = ZIPPacker.new()
    zip.open(outDir.path_join(out))
    
    var classList = ProjectSettings.get_global_class_list()
    var modClassList : Array[Dictionary] = []

    currentLabel.visible = true
    progressLabel.visible = true

    var i = 1
    for f in files:
        currentLabel.text = "Exporting " + f + "..."
        progressLabel.text = str(i) + "/" + str(files.size())
        progressBar.min_value = 0
        progressBar.step = 1
        progressBar.max_value = files.size()
        progressBar.value = i
        await get_tree().create_timer(0.01).timeout
        
        for c in classList:
            if c.path == f:
                modClassList.append(c)
                break

        if f == overrideCfgPath:
            zipAddFile(zip, f, "override.cfg")
        elif f != modCfgPath:
            addFile(zip, f)
            
        i += 1

    if modClassList.size() and includeGlobalScriptClassCache:
        currentLabel.text = "Writing class list..."
        await get_tree().create_timer(0.01).timeout
        var classListCfg = ConfigFile.new()
        classListCfg.set_value("", "list", modClassList)
        zipAddBuf(zip, ".godot/global_script_class_cache.cfg", classListCfg.encode_to_text().to_utf8_buffer())

    currentLabel.text = "Writing mod.txt..."
    await get_tree().create_timer(0.01).timeout
    if modCfgPath:

        # var modcfg = ConfigFile.new()
        # modcfg.load(modCfgPath)

        # # Store the remaps defined in the mod.txt remaps section
        # if modcfg.get_sections().has("remaps"):
        #     for src in modcfg.get_section_keys("remaps"):
        #         var remapCfg = ConfigFile.new()
        #         var override = modcfg.get_value("remaps", src)
        #         override = compiledRemaps.get(override, override)
        #         remapCfg.set_value("remap", "path", override)
        #         zipAddBuf(zip, src + ".remap", remapCfg.encode_to_text().to_utf8_buffer())
                
        #     # Remove the remaps section
        #     modcfg.erase_section("remaps")
        
        # # Store the mod.txt
        # zipAddBuf(zip, "mod.txt", modcfg.encode_to_text().to_utf8_buffer())

        # Rewritten procedure to avoid canonical formatting rules, so keys can have quotes
        # by Romero

        var fa = FileAccess.open(modCfgPath, FileAccess.READ)
        var mod_text := fa.get_as_text()
        fa.close()

        # var remaps = _extract_section(mod_text, "remaps")

        # mod_text = _remove_section(mod_text, "remaps")
        # zipAddBuf(zip, "mod.txt", mod_text.to_utf8_buffer())

        var remaps = _extract_section(mod_text, "remaps")

        if forceRemaps and remaps.size() > 0:
            for src in remaps:
                var override = remaps[src]

                # preserve quoted key exactly
                var clean_src = src.strip_edges().trim_prefix("\"").trim_suffix("\"")
                var clean_override = override.strip_edges().trim_prefix("\"").trim_suffix("\"")

                if clean_src.ends_with("*") and clean_override.ends_with("*"):
                    _expand_wildcard_remap(zip, clean_src, clean_override)
                    continue

                # fallback if global remap disabled, compiledRemaps will be empty (existing behavior)
                override = compiledRemaps.get(clean_override, clean_override)

                var remapCfg = ConfigFile.new()
                remapCfg.set_value("remap", "path", override)

                zipAddBuf(zip, clean_src + ".remap", remapCfg.encode_to_text().to_utf8_buffer())

            mod_text = _remove_section(mod_text, "remaps")

        zipAddBuf(zip, "mod.txt", mod_text.to_utf8_buffer())
    
    zip.close()
    currentLabel.text = "%s exported!" % out #"Done!"
    currentLabel.modulate = Color.LIME
    #OS.shell_show_in_file_manager(ProjectSettings.globalize_path(outDir.path_join(out)))
    
    if !exportTextTimer:
        exportTextTimer = get_tree().create_timer(10)
        
        exportTextTimer.timeout.connect(func():
            currentLabel.visible = false
            progressLabel.visible = false
            exportTextTimer = null
            )
    else:
        exportTextTimer.time_left = 10

func _extract_section(text: String, section: String) -> Dictionary:
    var result := {}
    var lines = text.split("\n")

    var in_section := false
    for line in lines:
        var trimmed = line.strip_edges()

        if trimmed.begins_with("[") and trimmed.ends_with("]"):
            in_section = (trimmed == "[" + section + "]")
            continue

        if in_section and "=" in trimmed:
            var parts = trimmed.split("=", false, 2)
            if parts.size() == 2:
                var key = parts[0].strip_edges()
                var value = parts[1].strip_edges()
                result[key] = value

    return result

func _remove_section(text: String, section: String) -> String:
    var lines = text.split("\n")
    var output: Array[String] = []

    var in_section := false

    for line in lines:
        var trimmed = line.strip_edges()

        if trimmed.begins_with("[") and trimmed.ends_with("]"):
            if trimmed == "[" + section + "]":
                in_section = true
                continue
            else:
                in_section = false

        if not in_section:
            output.append(line)

    return "\n".join(output)

func collectFiles(dir: String):
    # directories first
    for d in DirAccess.get_directories_at(dir):
        if d.ends_with(".git"):
            continue

        if _is_blacklisted(d, true):
            continue  # skip entire subtree early

        collectFiles(dir.path_join(d))

    # files
    for f in DirAccess.get_files_at(dir):
        if f == "mod.txt":
            continue

        if _is_blacklisted(f, false):
            continue

        # Skip .import files entirely if asset remap disabled
        if f.ends_with(".import") and not remapAssetsCheckbox.button_pressed:
            continue

        if dir.ends_with(".import"):
            continue

        files.append(dir.path_join(f))

func addFile(zip: ZIPPacker, path: String):
    var f: String = path.get_file()
    var dir: String = path.trim_suffix(f)

    var doRemap := remapCheckbox.button_pressed
    var doRemapAssets := remapAssetsCheckbox.button_pressed

    var importPath = dir.path_join(f + ".import")
    if FileAccess.file_exists(importPath) and doRemapAssets:
        var fa = FileAccess.open(importPath, FileAccess.ModeFlags.READ)
        var importCfg = ConfigFile.new()
        importCfg.parse(fa.get_as_text())
        fa.close()

        # Store dest files
        if importCfg.has_section_key("deps", "dest_files"):
            for df in importCfg.get_value("deps", "dest_files"):
                zipAddFile(zip, df)

        # Store the .import file 
        var remapCfg = ConfigFile.new()
        for k in importCfg.get_section_keys("remap"):
            if k == "generator_parameters": continue
            remapCfg.set_value("remap", k, importCfg.get_value("remap", k))
        zipAddBuf(zip, dir.path_join(f + ".import"), remapCfg.encode_to_text().to_utf8_buffer())
    else:
        # Convert text resources to binary ONLY if remapping enabled
        if (f.ends_with(".tres") || f.ends_with(".tscn")) and doRemap:
            # Convert to binary and store
            var binaryName = f.trim_suffix(".tres").trim_suffix(".tscn") + (".scn" if f.ends_with(".tscn") else ".res")
            var res: Resource = ResourceLoader.load(dir.path_join(f))

            if stripUidCheckbox.button_pressed:
                _strip_uids_recursive(res)
                _normalize_external_paths(res)
            var binOut = "res://.godot/exported".path_join(customResourceHash) \
                .path_join("export-" + dir.path_join(f).md5_text() + "-" + binaryName);
            ResourceSaver.save(res, binOut)
            zipAddFile(zip, binOut)

            # Save remap
            var remapCfg = ConfigFile.new()
            remapCfg.set_value("remap", "path", binOut)
            compiledRemaps[path] = binOut
            zipAddBuf(zip, dir.path_join(f + ".remap"), remapCfg.encode_to_text().to_utf8_buffer())
        else:
            # Store the file raw (no remap)
            if stripUidCheckbox.button_pressed and (f.ends_with(".tscn") or f.ends_with(".tres")):
                var fa = FileAccess.open(dir.path_join(f), FileAccess.READ)
                var text = fa.get_as_text()
                fa.close()

                text = _strip_uid_from_resource(text)
                zipAddBuf(zip, dir.path_join(f), text.to_utf8_buffer())
            else:
                zipAddFile(zip, dir.path_join(f))

func zipAddBuf(zip: ZIPPacker, path: String, buf: PackedByteArray):
    path = path.trim_prefix("res://")
    if path in zipPaths:
        return
        
    zip.start_file(path)
    zip.write_file(buf)
    zip.close_file()

    zipPaths.append(path)

func zipAddFile(zip: ZIPPacker, path: String, dest: String = ""):
    path = path.trim_prefix("res://")
    if path in zipPaths:
        return

    if dest == "":
        dest = path

    zip.start_file(dest)
    var fa = FileAccess.open("res://" + path, FileAccess.ModeFlags.READ)
    zip.write_file(fa.get_buffer(fa.get_length()))
    fa.close()
    zip.close_file()

    zipPaths.append(path)

func _init_regex():
    # remove uid="..."
    _uid_attr_regex.compile(' uid="uid://[^"]+"')
    _uid_any_regex.compile('uid://[^"]+')

func _strip_uid_from_resource(text: String) -> String:
    if _uid_attr_regex.get_pattern().is_empty():
        _init_regex()

    var lines = text.split("\n")
    var out: Array[String] = []

    for line in lines:
        var trimmed = line.strip_edges()

        # Strip uid from ext_resource
        if trimmed.begins_with("[ext_resource"):
            line = _uid_attr_regex.sub(line, "", true)

        # Strip uid from gd_resource header
        elif trimmed.begins_with("[gd_resource"):
            line = _uid_attr_regex.sub(line, "", true)

        # Strip `metadata/_custom_type_script = "uid://..."`
        elif trimmed.begins_with("metadata/_custom_type_script"):
            continue # drop line completely

        out.append(line)

    return "\n".join(out)

func _strip_uids_recursive(res: Resource) -> void:
    if not res:
        return

    # Remove UID from this resource
    if res.has_method("set_uid"):
        res.set_uid(0) # equivalent to INVALID
    elif "resource_uid" in res:
        res.resource_uid = 0

    # Traverse properties
    for prop in res.get_property_list():
        if prop.type == TYPE_OBJECT:
            var val = res.get(prop.name)
            if val is Resource:
                _strip_uids_recursive(val)

        elif prop.type == TYPE_ARRAY:
            var arr = res.get(prop.name)
            for v in arr:
                if v is Resource:
                    _strip_uids_recursive(v)

        elif prop.type == TYPE_DICTIONARY:
            var dict = res.get(prop.name)
            for v in dict.values():
                if v is Resource:
                    _strip_uids_recursive(v)

func _normalize_external_paths(res: Resource):
    for prop in res.get_property_list():
        if prop.type != TYPE_OBJECT:
            continue

        var val = res.get(prop.name)
        if val is Resource:
            var path = val.resource_path

            if path != "":
                # Force reload WITHOUT UID
                var clean = ResourceLoader.load(
                    path,
                    "",
                    ResourceLoader.CACHE_MODE_IGNORE
                )

                if clean:
                    res.set(prop.name, clean)
                    val = clean

            _normalize_external_paths(val)

func _expand_wildcard_remap(zip: ZIPPacker, src_pattern: String, dst_pattern: String) -> void:
    var src_dir: String = src_pattern.trim_suffix("*")
    var dst_dir: String = dst_pattern.trim_suffix("*")

    if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(src_dir)):
        push_warning("Wildcard source missing: " + src_dir)
        return

    var files: Array = DirAccess.get_files_at(src_dir)

    for f in files:
        # skip .import files explicitly
        if f.ends_with(".import"):
            continue

        var src_file: String = src_dir.path_join(f)
        var dst_file: String = dst_dir.path_join(f)

        # sanity check
        if not FileAccess.file_exists(dst_file):
            push_warning("Missing target file: " + dst_file)
            continue

        # optional but useful validation
        var import_path: String = dst_file + ".import"
        if not FileAccess.file_exists(import_path):
            push_warning("Missing .import for: " + dst_file)

        var remapCfg: ConfigFile = ConfigFile.new()
        remapCfg.set_value("remap", "path", dst_file)

        zipAddBuf(
            zip,
            src_file + ".remap",
            remapCfg.encode_to_text().to_utf8_buffer()
        )

func _parse_blacklist(input: String) -> PackedStringArray:
    var out: PackedStringArray = []
    for part in input.split("|"):
        var v = part.strip_edges().to_lower()
        v = v.trim_prefix(".") # allows using ".png|.psd" and "png|psd"
        if not v.is_empty():
            out.append(v)
    return out

func _is_blacklisted(name: String, is_dir: bool) -> bool:
    var lname = name.to_lower()

    # name blacklist (priority)
    for n in _nameBlacklist:
        if _exactMatch:
            if lname == n:
                return true
        else:
            if lname.contains(n):
                return true

    # extension blacklist (files only)
    if not is_dir:
        var ext = lname.get_extension()
        if not ext.is_empty() and ext in _extBlacklist:
            return true

    return false
