package main

// splitPaneWidths returns stable pane widths for a draggable two-pane layout.
// The ratio is clamped so that both panes remain usable even after aggressive resizing.
func splitPaneWidths(total, minLeft, minRight int32, ratio float64) (left, right int32, normalized float64) {
	if total <= 0 {
		return 0, 0, 0.5
	}
	if ratio < 0.25 {
		ratio = 0.25
	}
	if ratio > 0.68 {
		ratio = 0.68
	}
	if minLeft < 0 {
		minLeft = 0
	}
	if minRight < 0 {
		minRight = 0
	}
	// If the window is smaller than the requested minima, preserve a balanced,
	// ratio-driven split instead of producing negative geometry.
	if total < minLeft+minRight {
		minLeft = total / 3
		minRight = total / 3
	}
	left = int32(float64(total) * ratio)
	maxLeft := total - minRight
	if left < minLeft {
		left = minLeft
	}
	if left > maxLeft {
		left = maxLeft
	}
	if left < 0 {
		left = 0
	}
	if left > total {
		left = total
	}
	right = total - left
	normalized = float64(left) / float64(total)
	return
}

// historyDeleteReveal reports whether the pointer is inside the right half of a history item.
func historyDeleteReveal(left, right, x int32) bool {
	if right <= left {
		return false
	}
	return x >= left+(right-left)/2 && x <= right
}
