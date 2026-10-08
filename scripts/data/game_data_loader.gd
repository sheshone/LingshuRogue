class_name GameDataLoader
extends RefCounted


static func load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("数据文件不存在：%s" % path)
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("无法读取数据文件：%s" % path)
		return null

	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK:
		push_error("JSON 解析失败：%s（第 %d 行：%s）" % [path, json.get_error_line(), json.get_error_message()])
		return null

	return json.data


static func load_collection(path: String, collection_key: String) -> Array:
	var data: Variant = load_json(path)
	if not data is Dictionary:
		return []
	if not data.has(collection_key) or not data[collection_key] is Array:
		push_error("数据文件 %s 缺少数组字段：%s" % [path, collection_key])
		return []
	return data[collection_key]


static func index_by_id(entries: Array, source_name: String) -> Dictionary:
	var result := {}
	for entry: Variant in entries:
		if not entry is Dictionary or not entry.has("id"):
			push_warning("%s 中存在缺少 id 的条目，已忽略。" % source_name)
			continue
		var entry_id := str(entry["id"])
		if result.has(entry_id):
			push_warning("%s 中存在重复 id：%s，后者将覆盖前者。" % [source_name, entry_id])
		result[entry_id] = entry
	return result

