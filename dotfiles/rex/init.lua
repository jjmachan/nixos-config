-- Rex config: alt keys for panes and tabs (from Herdr).
-- Everything else uses Rex's defaults.

-- Panes: focus with alt+h/j/k/l, split with alt+\ (right) and alt+- (down)
rex.bind("alt+h", "pane.focus", { direction = "left" })
rex.bind("alt+j", "pane.focus", { direction = "down" })
rex.bind("alt+k", "pane.focus", { direction = "up" })
rex.bind("alt+l", "pane.focus", { direction = "right" })
rex.bind("alt+\\", "pane.split", { direction = "right" })
rex.bind("alt+-", "pane.split", { direction = "down" })

-- Tabs: new tab with alt+n, go to tab with alt+1..9, reorder with alt+i (left) and alt+o (right)
rex.bind("alt+n", "client.tab.new")
rex.bind("alt+1", "client.tab.goto", { index = 1 })
rex.bind("alt+2", "client.tab.goto", { index = 2 })
rex.bind("alt+3", "client.tab.goto", { index = 3 })
rex.bind("alt+4", "client.tab.goto", { index = 4 })
rex.bind("alt+5", "client.tab.goto", { index = 5 })
rex.bind("alt+6", "client.tab.goto", { index = 6 })
rex.bind("alt+7", "client.tab.goto", { index = 7 })
rex.bind("alt+8", "client.tab.goto", { index = 8 })
rex.bind("alt+9", "client.tab.goto", { index = 9 })
rex.bind("alt+i", "client.tab.move", { direction = "backward" })
rex.bind("alt+o", "client.tab.move", { direction = "forward" })
