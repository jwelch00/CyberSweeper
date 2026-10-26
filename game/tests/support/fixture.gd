class_name Fixture
extends RefCounted
## Builds solver positions from text, for hand-made pattern tests.
##
## Tokens are separated by spaces, one row per line:
##   0-8  revealed number      *  revealed mine
##   ?    hidden, unknown      -  known safe with no number (a wall)
## Everything outside the picture is a wall, so each pattern is self-contained.


static func solver(text: String, tier := 3, radius := 2) -> Solver:
	var s := Solver.new(tier, radius, 1000000)
	var rows := parse(text)
	var h := rows.size()
	var w := 0
	for row in rows:
		w = maxi(w, row.size())
	for y in range(-1, h + 1):
		for x in range(-1, w + 1):
			var c := Vector2i(x, y)
			var tok := "-"
			if y >= 0 and y < h and x >= 0 and x < rows[y].size():
				tok = rows[y][x]
			if tok == "?":
				continue
			elif tok == "*":
				s.add_mine(c)
			elif tok == "-":
				s.add_wall(c)
			else:
				s.add_number(c, int(tok))
	return s


static func parse(text: String) -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	for line in text.strip_edges().split("\n"):
		var toks := PackedStringArray()
		for t in line.strip_edges().split(" ", false):
			toks.append(t)
		rows.append(toks)
	return rows


## Cell at column x, row y of the picture.
static func at(x: int, y: int) -> Vector2i:
	return Vector2i(x, y)
