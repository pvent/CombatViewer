### CombatViewer
* **Description:** Provides a streamlined overlay or summary view of real-time combat metrics, event summaries, or encounter performance data tailored for the 2.5.3 environment.
* **How to Use:**
  1. Type the main slash command to toggle the viewer window.
  2. Inspect real-time data feeds during dungeons or raids.
* **Known Issues & Gotchas:**
  * **Memory Bloat:** Storing unpruned historical combat data arrays across long raid nights can cause memory usage to climb significantly. Periodic table pruning or garbage collection routines are recommended.
  * **Addon Dependencies:** Ensure all underlying library dependencies (such as LibStub or Ace3 modules) are bundled correctly within the repository structure to prevent load failures.
![Uploading image.png…]()
