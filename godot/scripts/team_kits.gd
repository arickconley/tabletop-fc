class_name TeamKits
extends RefCounted

const NAMES = ["Blue", "Red", "Orange", "Gold", "Green", "Mint", "Teal", "Violet", "Purple", "Pink", "Ivory", "Slate"]
const COLORS = [Color("2789eb"), Color("ee4964"), Color("ef8638"), Color("eac247"), Color("269866"), Color("82dab5"), Color("24b8c4"), Color("7867dc"), Color("ad4fbb"), Color("ed9abd"), Color("eee8d8"), Color("46596f")]
const DESIGNS = ["Plain", "Stripes", "Hoops"]

static func make(index: int, design: int = 0) -> Dictionary:
	index = clampi(index, 0, COLORS.size() - 1)
	return {"index": index, "name": NAMES[index], "color": COLORS[index], "design": clampi(design, 0, DESIGNS.size() - 1)}

static func opponents(index: int) -> Array[int]:
	var choices: Array[int] = []
	var ours: Color = COLORS[index]
	for i in COLORS.size():
		var other: Color = COLORS[i]
		var distance = Vector3(ours.r - other.r, ours.g - other.g, ours.b - other.b).length()
		var hue_gap = minf(absf(ours.h - other.h), 1.0 - absf(ours.h - other.h))
		if distance > 0.55 and (hue_gap > 0.12 or ours.s < 0.2 or other.s < 0.2):
			choices.append(i)
	return choices

static func opponent(index: int, random: RandomNumberGenerator) -> Dictionary:
	var choices = opponents(index)
	return make(choices[random.randi_range(0, choices.size() - 1)])

static func accent(kit: Dictionary) -> Color:
	return kit.color.lightened(0.32)
