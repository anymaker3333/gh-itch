extends RefCounted
## UI lifecycle smoke tests.
##
## The screens build widgets in a specific order - `configure()` first, `add_child()`
## second - and a widget that only sets itself up in `_ready()` breaks that contract
## with a runtime script error that the pure logic suites never see. These checks
## exercise the exact call order the screens use, headlessly.


func suite_name() -> String:
	return "ui smoke"


func run(h: TestHarness) -> void:
	_check_game_card(h)
	_check_card_face(h)


func _check_game_card(h: TestHarness) -> void:
	var entry := Catalog.get_entry("chess")
	h.check(entry != null, "chess is in the catalog")
	if entry == null:
		return
	var tree := Engine.get_main_loop() as SceneTree
	h.check(tree != null, "a SceneTree is available for UI smoke tests")
	if tree == null:
		return

	# Same order as library_screen._make_card: configure before entering the tree.
	var card := GameCard.new()
	card.configure(entry)
	h.is_true(card.get("_accent") != null, "GameCard builds its controls in configure()")
	h.is_true(card.get("_title") != null, "GameCard has a title label after configure()")
	if card.get("_title") != null:
		var title: Label = card.get("_title")
		h.equal(title.text, entry.display_name(), "card title shows the display name")
	tree.root.add_child(card)
	h.is_true(card.is_inside_tree(), "card enters the tree")
	h.is_true(card.get("_border") != null, "card keeps its controls after _ready() runs")
	card.free()

	# The other valid order: configure once the card is already in the tree.
	var late := GameCard.new()
	tree.root.add_child(late)
	late.configure(entry)
	h.is_true(late.get("_accent") != null, "configure() after _ready() also works")
	late.free()


func _check_card_face(h: TestHarness) -> void:
	var face := CardFace.new()
	face.configure({"id": "smoke", "title": "Smoke card", "cost": "3", "body": "Body", "glyph": "★"})
	var title: Label = face.get("_title")
	var glyph: Label = face.get("_glyph")
	h.is_true(title != null, "CardFace builds its controls in configure()")
	if title != null:
		h.equal(title.text, "Smoke card", "CardFace shows the title")
	h.is_true(glyph != null and glyph.visible, "a card with a glyph shows it")

	# Hierarchy: accent bar flush at the top, content inside the padded area.
	var column: Node = face.get_child(0)
	h.is_true(column.get_child_count() == 2, "the card column has exactly two rows")
	if column.get_child_count() == 2:
		h.is_true(column.get_child(0) is ColorRect, "the accent bar is the flush first row")
		var margin: Node = column.get_child(1)
		h.is_true(margin is MarginContainer, "the content row is the padded container")
		if title != null and margin is MarginContainer:
			h.is_true(title.get_parent().get_parent().get_parent() == margin, "inner content lives inside the padding")

	face.configure({"id": "smoke", "title": "Hidden", "face_down": true})
	h.is_true(glyph != null and glyph.visible and glyph.text == "✦", "face-down cards show the back glyph")
	face.configure({"id": "smoke", "title": "Plain"})
	h.is_true(glyph != null and not glyph.visible, "a card without a glyph hides it")
	face.free()
