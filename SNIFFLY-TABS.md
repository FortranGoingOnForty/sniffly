# tabs in sniffly

one thing that spacesniffer had that we dont is control of some kind of multi directory view

spacesniffer achieved this with something akin to panes
  - if i recall it was actually sub windows within the main window

I have a slightly different  vision.
I always found the panes approach to be cluttered. 

We have a natural space for a tab bar. It's on the far right on the same level as the breadcrumn
they'll be small to fit in the space but they'll have active highlighting with a yellowish border and maybe slight highlighting
you'll be able to navigate between tabs with cmd-<number key>
tabs will have small x's on them to close 
tabs open to the left, that is there's a small + button on the left side of the most recently made tab
the program starts in tab 0 (alt-1) by default.

we'll have to be careful about state. 
We'll have to be careful about scans in quicl succession or concurrent scans since that will require juggling many threads unless we can be smart about it and be clean and safe.

what other pitfalls do you see? Let's discuss and plan this feature'

