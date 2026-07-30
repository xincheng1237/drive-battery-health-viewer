package main

import "testing"

func TestSplitPaneWidthsDefaultHistoryRatio(t *testing.T) {
	left, right, ratio := splitPaneWidths(1000, 260, 340, 0.39)
	if left != 390 || right != 610 {
		t.Fatalf("got %d/%d", left, right)
	}
	if ratio < 0.389 || ratio > 0.391 {
		t.Fatalf("ratio %f", ratio)
	}
}

func TestSplitPaneWidthsClampsBothSides(t *testing.T) {
	left, right, _ := splitPaneWidths(800, 260, 340, 0.9)
	if left != 460 || right != 340 {
		t.Fatalf("right clamp: %d/%d", left, right)
	}
	left, right, _ = splitPaneWidths(800, 260, 340, 0.1)
	if left != 260 || right != 540 {
		t.Fatalf("left clamp: %d/%d", left, right)
	}
}

func TestSplitPaneWidthsTinyWindowNeverNegative(t *testing.T) {
	left, right, ratio := splitPaneWidths(300, 260, 340, 0.39)
	if left < 0 || right < 0 || left+right != 300 {
		t.Fatalf("invalid %d/%d", left, right)
	}
	if ratio <= 0 || ratio >= 1 {
		t.Fatalf("ratio %f", ratio)
	}
}

func TestHistoryDeleteRevealOnlyOnRightHalf(t *testing.T) {
	if historyDeleteReveal(0, 200, 99) {
		t.Fatal("left half revealed delete")
	}
	if !historyDeleteReveal(0, 200, 100) || !historyDeleteReveal(0, 200, 199) {
		t.Fatal("right half did not reveal delete")
	}
	if historyDeleteReveal(0, 200, 201) {
		t.Fatal("outside item revealed delete")
	}
}
