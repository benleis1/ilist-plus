;;; ilist-plus.el --- Extended imenu ilist support -*- lexical-binding: t; -*-

;;; Commentary:

;; ```
;;  o8o  oooo   o8o               .
;;  `"'  `888   `"'             .o8
;; oooo   888  oooo   .oooo.o .o888oo     88
;; `888   888  `888  d88(  "8   888       88
;;  888   888   888  `"Y88b.    888   8888888888
;;  888   888   888  o.  )88b   888 .     88
;; o888o o888o o888o 8""888P'   "888"     88
;; ```

;; Copyright (C) 2026 Benjamin Leis

;; SPDX-License-Identifier: MIT

;; Author:  Benjamin Leis <benleis1@gmail.com>

;; Maintainer: Benjamin Leis <benleis1@gmail.com>

;; Version: 0.0.3

;; Package-Requires: ((emacs "29") (diff-hl "20260830.1400"))

;; Keywords: convenience outlines tools

;; URL: https://github.com/benleis1/ilist-plus

;; **BETA release**

;; This package inspired by Emac's imenu-list provides a richer outline sidebar.
;; It adds hierarchical folding, sorting, Git modification indicators, improved styling and better
;; indexing for elisp, org and treesitter java. If you use imenu-list to navigate large files,
;; ilist-plus make the outline substantially more informative and interactive. Stock imenu-list
;; gives you a flat, ordered by position index; these extensions turn it into a more dynamic outline
;; by leveraging hierarchy and folding strategies, so the side window tracks where you are and how
;; deep you are without extra effort.

;; ## Samples
;; ![Before - with just imenu-ilist](./before.png)
;;    This shows what imenu-list looks like by itself.
;;
;; ![After - with ilist-plus](./after.png) This shows what ilist-plus changes immediately. Note: the
;;    new hierarchy based on the elisp header comments and autofolding.
;;
;; ![More Details](./demo3.png) One of the ascii tree styles and some additional feature callouts.
;;
;; ![Folding Behavior](./demo2.gif)
;;    The dynamic folding behavior.

;; ## UI
;; * Collapsible arrow icons and several ascii tree formatting styles.
;; * menu entry sorting (alphabetical/postion etc.)
;; * custom mode-line formatting
;; * a new face for highlighting the current location
;; * default autofolding levels. For example: autofold every node deeper than 2 levels on initial open.
;; * auto unfolding for the current node the cursor is located at.

;; ## Semantics
;; * Integration with diff-hl to visually show which entries are modified.
;; * Expanded hierarchical indexing for elisp that parse header/subheader comments and organize based on that.
;; * Expanded hierarchical indexing for treesitter java mode
;; * perf optimization for org mode.

;; ## Requirements
;; 1. Recommended: modus-themes loaded with a theme active — modus-themes-get-color-value is called
;;    at defface time for ilist-plus-hl-face and ilist-plus-modified-face.
;; 2. Recommended: a fg-hl-imenu entry in modus-themes-common-palette-overrides — without it the
;;      highlight face has no foreground color.
;; 3. diff-hl package + global-diff-hl-mode enabled, for the VC-modified highlighting to work

;; ## Backwards Compatibility
;; * The lastest implementation no longer extends imenu-list and instead fully replaces it.
;; * To keep an existing imenu-list configuration, see `ilist-plus-imenu-list-compat`.
;;
;; ## Installing
;; 1. Install this package using `use-package`
;; ```
;;  (use-package ilist-plus
;;    :vc (:url "https://github.com/benleis1/ilist-plus"))
;; ```
;; 2. Turn on `ilist-plus-mode` (a global minor mode) to install its
;;    mode-line format and hooks,
;; ```
;; (ilist-plus-mode 1)
;; ```
;; 3. Hookup the elisp and/or java indexers (ilist-plus-elisp-index and ilist-plus-java-ts-index)
;;   in a hook with a default autofold depth.
;;
;; ```
;; (add-hook 'emacs-lisp-mode-hook
;;                 (lambda ()
;;             	      (setq-local ilist-plus-autofold-depth 2)
;;                    (setq-local imenu-create-index-function 'ilist-plus-elisp-index)))
;; ```
;; 4. Turn on the side window by calling `ilist-plus-toggle`. Every frame has its own outline buffer,
;;    `*IListPlus[N]*`, that tracks, folds and toggles independently of the other frames.
;;
;; ## Customization
;; * The tree style is set via the custom variable `ilist-plus-tree-style`.
;; * Window and update behavior: `ilist-plus-position`, `ilist-plus-size`,
;;   `ilist-plus-focus-after-activation`, `ilist-plus-auto-resize`, `ilist-plus-update-current-entry`,
;;   `ilist-plus-auto-update`, `ilist-plus-idle-update-delay`, `ilist-plus-after-jump-hook` and
;;   `ilist-plus-update-hook`.
;; * Set `ilist-plus-imenu-list-compat` to non-nil to have ilist-plus read the matching `imenu-list-*`
;;   options (and hooks, and the `imenu-list` entry faces) when they are defined. Off by default.
;; * Set fg-hl-imenu to some color in a modus palette override to set the foreground color for the current
;; entry
;;

;; ## Key bindings
;; Bindings active in the `*IListPlus[N]*` buffers (`ilist-plus-major-mode-map`). Rows marked `*` are
;; bindings that stock imenu-list does not have.
;;
;; | Key              | Command                      | Description                                          |
;; |------------------|-------------------------------|-------------------------------------------------------|
;; | `RET` / `mouse-2`| `ilist-plus-ret-dwim`        | Jump to the entry at point                            |
;; | `SPC`            | `ilist-plus-display-dwim`    | Display the entry without leaving the Ilist buffer    |
;; | `TAB` *          | `ilist-plus-toggle-at-point` | Toggle fold/unfold of the entry at point               |
;; | `f` *            | `ilist-plus-toggle-fold-all` | Toggle the whole tree between fully unfolded and the autofold depth |
;; | `s` *            | `ilist-plus-switch-sort`     | Switch sort strategy (alphabetical / position / by-type) |
;; | `n`              | `next-line`                   | Move to the next entry                                 |
;; | `p`              | `previous-line`               | Move to the previous entry                             |
;; | `g`              | `ilist-plus-refresh`         | Refresh the index                                      |
;; | `q`              | `ilist-plus-quit-window`     | Close this frame's Ilist window                        |
;; | `mouse-1` *      | `quit-window`                 | Click the Ilist mode-line to close the window          |

;; ## Demo video
;; [Link](https://www.youtube.com/watch?v=NU2WcX4dDiU)

;;; Code:

;; ilist-plus renders and tracks its own outline buffers (one `*IListPlus[N]*' per frame). See
;; `ilist-plus-imenu-list-compat' to reuse an existing imenu-list configuration.
(require 'imenu)
(require 'cl-lib)
(require 'hl-line)

;; pre-declarations

(declare-function treesit-node-children treesit.el)
(declare-function treesit-node-text treesit.el)
(declare-function treesit-buffer-root-node treesit.el)
(declare-function imenu--subalist-p imenu.el)
(declare-function imenu--generic-function imenu.el)
(declare-function eglot--lsp-position-to-point "eglot")
(declare-function eglot-managed-p "eglot")
(declare-function window--display-buffer window.el)

(defvar imenu--index-alist)

;;; General UI changes
(defgroup ilist-plus nil
  "Sidebar that represents the imenu entries."
  :group 'convenience)

;;; Options

;; Because this package originally extended imenu-list and now has decoupled provide a compat layer
;; for migration.
(defcustom ilist-plus-imenu-list-compat nil
  "Whether ilist-plus honors an existing `imenu-list' configuration.
When non-nil, each of the `imenu-list' options that has an ilist-plus
counterpart below (position, size, focus-after-activation, auto-resize,
update-current-entry, `idle-update-delay', auto-update,
persist-when-imenu-index-unavailable, `mode-line-format',
custom-position-translator and the `imenu-list-after-jump-hook' and
`imenu-list-update-hook' hooks) is read from its `imenu-list-*'
variable whenever that variable is bound, in preference to the
`ilist-plus-*' one.  `imenu-list' itself is never loaded by ilist-plus."
  :type 'boolean
  :group 'ilist-plus)

(defcustom ilist-plus-position 'right
  "Side of the frame the Ilist window is on: `right', `left', `above' or `below'."
  :type '(choice (const above) (const below) (const left) (const right))
  :group 'ilist-plus)

(defcustom ilist-plus-size 0.3
  "Size of the Ilist window: a fraction of the frame, or a number of rows/columns."
  :type 'number
  :group 'ilist-plus)

(defcustom ilist-plus-focus-after-activation t
  "Non-nil to select the Ilist window when it is opened."
  :type 'boolean
  :group 'ilist-plus)

(defcustom ilist-plus-auto-resize nil
  "Non-nil to resize the Ilist window to fit its content after each update."
  :type 'boolean
  :group 'ilist-plus)

(defcustom ilist-plus-update-current-entry t
  "Non-nil to keep the Ilist point on the entry the source window is in."
  :type 'boolean
  :group 'ilist-plus)

(defcustom ilist-plus-auto-update t
  "Non-nil to update visible Ilist windows whenever Emacs is idle."
  :type 'boolean
  :group 'ilist-plus)

(defcustom ilist-plus-idle-update-delay 0.5
  "Idle time in seconds before the Ilist windows are updated."
  :type 'number
  :group 'ilist-plus)

(defcustom ilist-plus-persist-when-imenu-index-unavailable t
  "Non-nil to keep the old entries when the new source buffer has no imenu index."
  :type 'boolean
  :group 'ilist-plus)

(defcustom ilist-plus-custom-position-translator nil
  "Function returning a function that maps an imenu position to a buffer position.
Nil means imenu positions are used as they are."
  :type '(choice (const nil) function)
  :group 'ilist-plus)

(defcustom ilist-plus-after-jump-hook '(recenter)
  "Hook run after jumping to an entry from an Ilist buffer."
  :type 'hook
  :group 'ilist-plus)

(defcustom ilist-plus-update-hook nil
  "Hook run, with the source buffer current, after an Ilist buffer is updated."
  :type 'hook
  :group 'ilist-plus)

(defvar ilist-plus-mode-line-format nil
  "Mode-line format of the Ilist buffers, set by `ilist-plus-mode'.")

(defun ilist-plus--opt (name)
  "The value of option NAME (a symbol such as `size').
Reads `imenu-list-NAME' when `ilist-plus-imenu-list-compat' is set and
that variable is bound, otherwise `ilist-plus-NAME'."
  (let ((compat (intern (format "imenu-list-%s" name))))
    (if (and ilist-plus-imenu-list-compat (boundp compat))
        (symbol-value compat)
      (symbol-value (intern (format "ilist-plus-%s" name))))))

(defun ilist-plus--run-hooks (name)
  "Run hook NAME's `ilist-plus-' variant, then its `imenu-list-' one under compat."
  (run-hooks (intern (format "ilist-plus-%s" name)))
  (let ((compat (intern (format "imenu-list-%s" name))))
    (when (and ilist-plus-imenu-list-compat (boundp compat))
      (run-hooks compat))))

;;; Per-frame buffers

;; Every frame gets its own outline buffer, named `*IListPlus[N]*' where N is a small
;; per-frame id, so each frame tracks and folds independently.  All of a buffer's
;; state lives in buffer-local variables of that Ilist buffer.

(defvar-local ilist-plus--frame nil
  "The frame this `*IListPlus[N]*' buffer belongs to.")

(defvar-local ilist-plus--entries nil
  "The imenu index of `ilist-plus--source', as shown in this Ilist buffer.")

(defvar-local ilist-plus--line-entries nil
  "Entries of `ilist-plus--entries' in display order, one per line.")

(defvar-local ilist-plus--source nil
  "The buffer whose imenu index this Ilist buffer displays.")

(defvar-local ilist-plus--last-location nil
  "Marker where this Ilist buffer was last updated from; avoids redundant updates.")

(defun ilist-plus--frame-id (frame)
  "The small positive integer naming FRAME's Ilist buffer.
Assigned on first use as the lowest id not held by another frame."
  (or (frame-parameter frame 'ilist-plus-id)
      (let ((used (delq nil (mapcar (lambda (f) (frame-parameter f 'ilist-plus-id))
                                    (frame-list))))
            (id 1))
        (while (memq id used)
          (setq id (1+ id)))
        (set-frame-parameter frame 'ilist-plus-id id)
        id)))

(defun ilist-plus--buffer-name (&optional frame)
  "Name of FRAME's (default: the selected frame's) Ilist buffer."
  (format "*IListPlus[%d]*" (ilist-plus--frame-id (or frame (selected-frame)))))

(defun ilist-plus--buffer (&optional frame)
  "FRAME's (default: the selected frame's) Ilist buffer, or nil if it has none."
  (get-buffer (ilist-plus--buffer-name frame)))

(defun ilist-plus--ilist-buffer-p (buffer)
  "Non-nil if BUFFER is a live Ilist buffer."
  (and (buffer-live-p buffer)
       (eq (buffer-local-value 'major-mode buffer) 'ilist-plus-major-mode)))

(defun ilist-plus--buffers ()
  "All live Ilist buffers."
  (let (result)
    (dolist (buffer (buffer-list))
      (when (ilist-plus--ilist-buffer-p buffer)
        (push buffer result)))
    (nreverse result)))

(defun ilist-plus--frame-deleted (frame)
  "Kill FRAME's Ilist buffer when FRAME goes away."
  (let ((buffer (ilist-plus--buffer frame)))
    (when buffer
      (kill-buffer buffer))))

(defun ilist-plus--get-buffer (&optional frame)
  "Create or return the  FRAME's  IlistPlus buffer.
Default to the current frame if FRAME isn't supplied."
  (let* ((frame (or frame (selected-frame)))
         (buffer (get-buffer-create (ilist-plus--buffer-name frame))))
    (with-current-buffer buffer
      (unless (derived-mode-p 'ilist-plus-major-mode)
        (ilist-plus-major-mode))
      (setq ilist-plus--frame frame))
    buffer))

(defun ilist-plus--current-ibuf ()
  "Return the current ilistplus buffer for the given buffer."
  (cond ((ilist-plus--ilist-buffer-p (current-buffer)) (current-buffer))
        ((ilist-plus--buffer))
        (t (user-error "No Ilist buffer for this frame"))))

(defun ilist-plus--window (ibuf)
  "The window showing IBUF in any frame, or nil."
  (get-buffer-window ibuf t))

;; Faces for the outline entries, by depth (depth 3 and deeper share one).  Containers are bold
;; without underlining.
(defface ilist-plus-face
  '((t))
  "Parent face for all Ilist entry faces."
  :group 'ilist-plus)

(defface ilist-plus-entry-face
  '((t :inherit ilist-plus-face))
  "Base face for Ilist entries at every depth."
  :group 'ilist-plus)

(defface ilist-plus-entry-face-0
  '((((class color) (background light)) :inherit ilist-plus-entry-face :foreground "maroon")
    (((class color) (background dark)) :inherit ilist-plus-entry-face :foreground "gold"))
  "Face for outermost Ilist entries (depth 0)."
  :group 'ilist-plus)

(defface ilist-plus-entry-container-face-0
  '((t :inherit ilist-plus-entry-face-0 :weight bold))
  "Face for container entries at depth 0."
  :group 'ilist-plus)

(defface ilist-plus-entry-face-1
  '((((class color) (background light)) :inherit ilist-plus-entry-face :foreground "dark green")
    (((class color) (background dark)) :inherit ilist-plus-entry-face :foreground "light green"))
  "Face for Ilist entries at depth 1."
  :group 'ilist-plus)

(defface ilist-plus-entry-container-face-1
  '((t :inherit ilist-plus-entry-face-1 :weight bold))
  "Face for container entries at depth 1."
  :group 'ilist-plus)

(defface ilist-plus-entry-face-2
  '((((class color) (background light)) :inherit ilist-plus-entry-face :foreground "dark blue")
    (((class color) (background dark)) :inherit ilist-plus-entry-face :foreground "light blue"))
  "Face for Ilist entries at depth 2."
  :group 'ilist-plus)

(defface ilist-plus-entry-container-face-2
  '((t :inherit ilist-plus-entry-face-2 :weight bold))
  "Face for container entries at depth 2."
  :group 'ilist-plus)

(defface ilist-plus-entry-face-3
  '((((class color) (background light)) :inherit ilist-plus-entry-face :foreground "orange red")
    (((class color) (background dark)) :inherit ilist-plus-entry-face :foreground "sandy brown"))
  "Face for Ilist entries at depth 3 and deeper."
  :group 'ilist-plus)

(defface ilist-plus-entry-container-face-3
  '((t :inherit ilist-plus-entry-face-3 :weight bold))
  "Face for container entries at depth 3 and deeper."
  :group 'ilist-plus)

(defvar ilist-plus-fixed-font (face-attribute 'default :family))

;; Be care to set the font family to one with nerd fonts so the icon renders.
(defface ilist-plus-icon-face
  `((t (:inherit (mode-line-buffer-id ilist-plus-face) :family ,ilist-plus-fixed-font)))
  "Face for the icon glyphs in `imenu-list-mode-line-format'."
  :group 'ilist-plus)

;; `modus-themes' is optional,
;; fall back to a plain color when it isn't loaded, since `defface' below
;; evaluates this at package-load time, not lazily.
(defun ilist-plus--modus-color (name overrides &optional fallback)
  "Get the modus controlled color NAME with OVERRIDES and a FALLBACK color."
  (if (fboundp 'modus-themes-get-color-value)
      (modus-themes-get-color-value name overrides)
    (or fallback "black")))

;; `mode-line-highlight' usually draws a box, which adds pixels around the hovered text and shifts
;; the icon; drop the box so hovering only changes colors.
(defface ilist-plus-mode-line-highlight
  '((t (:inherit mode-line-highlight :box nil)))
  "Face for the hovered parts of the Ilist mode-line."
  :group 'ilist-plus)

(defvar ilist-plus-default-key-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mode-line mouse-1] #'quit-window)
    map)
  "Default keymap for the modeline.")

(defvar ilist-plus-sort-map
  (let ((map (make-sparse-keymap)))
    (define-key map [mode-line mouse-1] #'ilist-plus-cycle-sort)
    (define-key map [header-line mouse-1] #'ilist-plus-cycle-sort)
    map)
  "Keymap of the sort indicator in the Ilist mode-line.")

(defun ilist-plus-mode-line-icon ()
  "The Ilist mode-line icon, propertized with `ilist-plus-icon-face'."
  (propertize "󰉹" 'face 'ilist-plus-icon-face))

(defun ilist-plus-mode-line-sort ()
  "The clickable \"[sort]\" indicator of the current Ilist buffer."
  (propertize (format "[%s]" (ilist-plus-current-sort ilist-plus--source))
              'help-echo "mouse-1: switch the sort order"
              'mouse-face 'ilist-plus-mode-line-highlight
              'local-map ilist-plus-sort-map))

(defun ilist-plus-mode-line-label ()
  "Icon, source buffer name and sort indicator of the current Ilist buffer.
Nil when the source buffer is gone."
  (when (buffer-live-p ilist-plus--source)
    (concat (ilist-plus-mode-line-icon) " "
            (propertize (buffer-name ilist-plus--source) 'face 'mode-line-buffer-id)
            "  " (ilist-plus-mode-line-sort))))

(defun ilist-plus--build-mode-line-format (&optional key-map)
  "Build the Ilist mode-line format, with KEY-MAP on all but the sort indicator."
  `("%e"
    (:propertize
     ("" mode-line-frame-identification
      (:eval (ilist-plus-mode-line-icon)) " "
      (:eval (and (buffer-live-p ilist-plus--source) (buffer-name ilist-plus--source))))
     help-echo "mouse-1: close the window"
     mouse-face ilist-plus-mode-line-highlight
     local-map ,(or key-map ilist-plus-default-key-map))
    "  " (:eval (ilist-plus-mode-line-sort)) "  "
    mode-line-end-spaces))

(defconst ilist-plus-collapsed-marker "▶"
  "Marker shown for a folded (hidden) entry.
In the `classic' `ilist-plus-tree-style' it replaces the leading \"+\";
in `straight'/`curved' it replaces the container's own connector cell.
Shared by all three styles.")

(defconst ilist-plus-expanded-marker "▼"
  "Marker shown before an unfolded (visible) entry.
In the `classic' `ilist-plus-tree-style'. `straight'/`curved' show no
marker at all when expanded -- the tree lines already convey the
structure.")

(defun ilist-plus--set-tree-style (symbol value)
  "`:set' function for SYMBOL and VALUE with `ilist-plus-tree-style'.
Applies VALUE, then redraws every *IListPlus[N]* buffer so the change is
visible right away instead of waiting for the next unrelated refresh."
  (set-default symbol value)
  (dolist (ibuf (ilist-plus--buffers))
    (ilist-plus--refresh ibuf)))

(defcustom ilist-plus-tree-style 'classic
  "Visual style used to render *IlistPlus* entry indentation and folds.
`classic'  -- imenu-list's original look: plain indentation with a
              leading \"+ \" marker (swapped for ▶/▼ by ilist-plus).
`straight' -- unicode box-drawing tree lines (├─ └─ │); a collapsed
              container's own connector is replaced by ▶, and an
              expanded container shows no marker at all.
`curved'   -- same as `straight' but with rounded corners (╰─ instead
              of └─); the collapsed marker is the same ▶ glyph."
  :type '(choice (const :tag "Classic (+/indent)" classic)
                 (const :tag "Straight tree lines" straight)
                 (const :tag "Curved tree lines" curved))
  :set #'ilist-plus--set-tree-style
  :group 'ilist-plus)

;; I need a more visible highlight for the current block
(defface ilist-plus-hl-face
  `((t (:inherit ilist-plus-face :foreground ,(ilist-plus--modus-color 'fg-hl-imenu t) :weight bold)))
  "A new custom face for highlighting."
  :group 'ilist-plus)

;;; Tree-line rendering (`straight'/`curved' `ilist-plus-tree-style')
;;
;; `imenu-list-insert-entries' (advised below, `classic' style
;; untouched) builds each line as: an ancestor-guide prefix (one
;; 3-char cell per ancestor level -- "│  " if that ancestor has later
;; siblings, "   " if it was the last child), then, for entries below
;; the root, a 3-char branch cell ("├─ "/"└─ " or "╰─ " when curved).
;; A container's own branch cell is tagged with the `ilist-plus-fold-marker' text
;; property so `ilist-plus--set-marker-at-point' can find and replace
;; it with `ilist-plus-collapsed-marker' once the container is
;; folded, without ever changing the line's length -- folding only
;; ever toggles a `display' override on that fixed-width span.

(cl-defstruct (ilist-plus--node (:constructor ilist-plus--node-create)
                                (:copier nil))
  "One line of the outline, built by `ilist-plus--build-nodes'.
It holds what the renderer and the fold code need to know about a line,
so neither has to thread depth or sibling state through recursion."
  (entry nil :documentation "The imenu entry shown on the line.")
  (depth 0 :documentation "Nesting depth; 0 for top-level entries.")
  (last-child nil
              :documentation "Non-nil if the entry is last among its siblings.")
  (ancestor-last-children
   nil
   :documentation "The `last-child' of each ancestor, outermost first.
Top-level entries are not drawn as a parent, so they are left out.")
  (path nil
        :documentation "Names of the entry and its ancestors, outermost first.")
  (container-p nil :documentation "Non-nil if the entry has children."))

(defun ilist-plus--node-level (node)
  "Return NODE's 1-based depth.
Top-level entries are level 1, as `ilist-plus-autofold-depth' counts them."
  (1+ (ilist-plus--node-depth node)))

(defun ilist-plus--build-nodes (index-alist)
  "Return INDEX-ALIST flattened into `ilist-plus--node's, in display order."
  (let (nodes)
    (cl-labels
        ((walk (alist ancestor-last-children path)
           (let ((count (length alist))
                 (depth (length path))
                 (i 0))
             (dolist (entry alist)
               (let ((last-child (= i (1- count)))
                     (entry-path (append path (list (car entry))))
                     (container-p (and (imenu--subalist-p entry) t)))
                 (push (ilist-plus--node-create
                        :entry entry :depth depth :last-child last-child
                        :ancestor-last-children ancestor-last-children
                        :path entry-path :container-p container-p)
                       nodes)
                 (when container-p
                   ;; Top-level entries are independent headings, not siblings
                   ;; under a drawn parent, so their own `last-child' never
                   ;; feeds a trunk line.
                   (walk (cdr entry)
                         (if (= depth 0)
                             nil
                           (append ancestor-last-children (list last-child)))
                         entry-path)))
               (setq i (1+ i))))))
      (walk index-alist nil nil))
    (nreverse nodes)))

(defun ilist-plus--tree-ancestor-prefix (ancestor-last-children)
  "Return the ancestor-guide prefix for ANCESTOR-LAST-CHILDREN.
ANCESTOR-LAST-CHILDREN lists, outermost to immediate parent, whether
each ancestor was the last child among its own siblings."
  (mapconcat (lambda (last-child) (if last-child "   " "│  "))
             ancestor-last-children ""))

(defun ilist-plus--tree-branch (last-child style)
  "Return the 3-char branch string for an entry drawn in STYLE.
LAST-CHILD non-nil means the entry is last among its siblings.  STYLE is
`straight' or `curved'; the corner glyph is the only difference between
them.  The collapsed marker that can later replace this whole cell (see
`ilist-plus-collapsed-marker') is shared by both."
  (concat (if last-child (if (eq style 'curved) "╰" "└") "├") "─ "))

(defun ilist-plus--get-face (depth subalistp)
  "The face for an entry at DEPTH and SUBALISTP for containers.
Under `ilist-plus-imenu-list-compat' the `imenu-list' faces are used
when they exist, so their customizations carry over."
  (let ((level (min depth 3)))
    (or (and ilist-plus-imenu-list-compat
             (let ((face (intern (format (if subalistp
                                             "imenu-list-entry-subalist-face-%d"
                                           "imenu-list-entry-face-%d")
                                         level))))
               (and (facep face) face)))
        (intern (format (if subalistp
                            "ilist-plus-entry-container-face-%d"
                          "ilist-plus-entry-face-%d")
                        level)))))

(defun ilist-plus--button-position (button)
  "Buffer position of BUTTON as handed to a button action."
  (cond ((overlayp button) (overlay-start button))
        ((integer-or-marker-p button) button)
        ((eventp button) (posn-point (event-end button)))
        (t (point))))

(defun ilist-plus--action-goto-entry (button)
  "Button action: jump to the entry BUTTON labels."
  (goto-char (ilist-plus--button-position button))
  (ilist-plus-goto-entry))

(defun ilist-plus--action-toggle (button)
  "Button action: fold/unfold the container BUTTON labels."
  (goto-char (ilist-plus--button-position button))
  (ilist-plus-toggle-at-point))

(defun ilist-plus--depth-string (depth)
  "Indentation prefix for an entry at DEPTH in the `classic' style."
  (if (> depth 0) (concat (make-string (* 2 depth) ?\s) " ") ""))

(defun ilist-plus--insert-node-classic (node)
  "Insert the `classic'-style line for NODE."
  (let ((entry (ilist-plus--node-entry node))
        (depth (ilist-plus--node-depth node)))
    (insert (ilist-plus--depth-string depth))
    (if (ilist-plus--node-container-p node)
        (insert-button (format "+ %s" (car entry))
                       'face (ilist-plus--get-face depth t)
                       'help-echo (format "Toggle: %s" (car entry))
                       'follow-link t
                       'action #'ilist-plus--action-toggle)
      (insert-button (format "%s" (car entry))
                     'face (ilist-plus--get-face depth nil)
                     'help-echo (format "Go to: %s" (car entry))
                     'follow-link t
                     'action #'ilist-plus--action-goto-entry))
    (insert "\n")))

(defun ilist-plus--insert-node-tree (node style)
  "Insert the tree-style line for NODE, drawn in STYLE.
STYLE is `straight' or `curved'.

For a container, its own connector cell is part of the button's label,
not text inserted ahead of it, so a click anywhere on the connector
toggles the fold, the same as clicking the leading \"+\" does in
`classic' style.  A leaf's branch cell stays outside its button,
matching `classic', where the indentation ahead of a leaf's name is
likewise unclickable."
  (let ((entry (ilist-plus--node-entry node))
        (depth (ilist-plus--node-depth node))
        (last-child (ilist-plus--node-last-child node)))
    (insert (ilist-plus--tree-ancestor-prefix
             (ilist-plus--node-ancestor-last-children node)))
    (if (ilist-plus--node-container-p node)
        (let* ((connector (if (= depth 0)
                              ""
                            (ilist-plus--tree-branch last-child style)))
               (btn-beg (point)))
          (insert-button (concat connector (format "%s" (car entry)))
                         'face (ilist-plus--get-face depth t)
                         'help-echo (format "Toggle: %s" (car entry))
                         'follow-link t
                         'action #'ilist-plus--action-toggle)
          (when (> (length connector) 0)
            (put-text-property btn-beg (+ btn-beg (length connector))
                               'ilist-plus-fold-marker t)))
      (when (> depth 0)
        (insert (ilist-plus--tree-branch last-child style)))
      (insert-button (format "%s" (car entry))
                     'face (ilist-plus--get-face depth nil)
                     'help-echo (format "Go to: %s" (car entry))
                     'follow-link t
                     'action #'ilist-plus--action-goto-entry))
    (insert "\n")))

(defun ilist-plus--insert-entries ()
  "Rebuild the current IlistPlus buffer."
  (let ((inhibit-read-only t)
        (nodes (ilist-plus--build-nodes ilist-plus--entries)))
    (erase-buffer)
    (dolist (node nodes)
      (if (eq ilist-plus-tree-style 'classic)
          (ilist-plus--insert-node-classic node)
        (ilist-plus--insert-node-tree node ilist-plus-tree-style)))
    (setq ilist-plus--line-entries (mapcar #'ilist-plus--node-entry nodes))))

(defun ilist-plus--set-marker-at-point ()
  "Set the fold marker on the current line."
  (save-excursion
    (beginning-of-line)
    (let* ((eol (line-end-position))
           ;; Our fold overlays start at the beginning of the *next*
           ;; line (see `ilist-plus--line-span'),
           (folded (ilist-plus--folded-p (min (point-max) (1+ eol))))
           (inhibit-read-only t))
      (if (eq ilist-plus-tree-style 'classic)
          (when (looking-at "^ *\\(\\+\\) ")
            (put-text-property (match-beginning 1) (match-end 1)
                               'display
                               (if folded
                                   ilist-plus-collapsed-marker
                                 ilist-plus-expanded-marker)))
        (let ((slot-beg (text-property-any (point) eol 'ilist-plus-fold-marker t)))
          (when slot-beg
            (let ((slot-end (next-single-property-change slot-beg 'ilist-plus-fold-marker nil eol)))
              (put-text-property slot-beg slot-end 'display
                                 (when folded
                                   (concat ilist-plus-collapsed-marker
                                           (make-string (1- (- slot-end slot-beg)) ?\s)))))))))))

(defun ilist-plus-update-fold-markers (&optional buffer)
  "Update every foldable entry's marker in BUFFER."
  (with-current-buffer (or buffer (ilist-plus--current-ibuf))
    (ilist-plus--rebind-buttons)
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (ilist-plus--set-marker-at-point)
        (forward-line 1)))))

;;; Direct, hideshow-free folding.
;; Emacs 31 rewrote hideshow.el, and its new engine has a reproducible
;; bug where hiding several blocks within one command silently fails
;; partway through, with no error -- confirmed across every hideshow
(defvar ilist-plus--invisible-spec 'ilist-plus-fold
  "Symbol used as the `invisible' overlay property for folded *Ilist* blocks.")

(defun ilist-plus--hide-region (beg end)
  "Fold BEG..END in the *Ilist* buffer via our own overlay."
  (let ((ov (make-overlay beg end)))
    (overlay-put ov 'invisible ilist-plus--invisible-spec)
    (overlay-put ov 'ilist-plus-fold t)
    (overlay-put ov 'evaporate t)
    ov))

(defun ilist-plus--show-region (beg end)
  "Unfold BEG..END in the *Ilist* buffer."
  (remove-overlays beg end 'ilist-plus-fold t))

(defun ilist-plus--folded-p (pos)
  "Non-nil if our fold overlay covers POS."
  (eq (get-char-property pos 'invisible) ilist-plus--invisible-spec))

(defun ilist-plus--any-folded-p ()
  "Return if any container in the IListPlus buffer is currently folded."
  (let (found)
    (dolist (ov (overlays-in (point-min) (point-max)))
      (when (overlay-get ov 'ilist-plus-fold)
        (setq found t)))
    found))

(defun ilist-plus--subtree-end (nodes n start)
  "Return the index of the first node after START outside START's subtree.
NODES is the list of `ilist-plus--node's and N its length.  Return N
when the subtree runs to the end."
  (let ((i (1+ start))
        (depth (ilist-plus--node-depth (nth start nodes))))
    (while (and (< i n) (> (ilist-plus--node-depth (nth i nodes)) depth))
      (setq i (1+ i)))
    i))

(defun ilist-plus--line-span (n i end-i)
  "Character range to hide for the subtree at line I.
Calculated from the start of line I+1 (i.e. *after* I's own header line
  and its newline, so the header keeps its own line break and stays on
  its own visual line) to the start of line END-I (or `point-max' if
  END-I runs past the last entry, of N total)."
  (save-excursion
    (goto-char (point-min))
    (forward-line (1+ i))
    (let ((beg (point)))
      (cons beg (if (>= end-i n)
                    (point-max)
                  (goto-char (point-min))
                  (forward-line end-i)
                  (point))))))

(defvar ilist-plus-major-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'ilist-plus-ret-dwim)
    (define-key map (kbd "SPC") #'ilist-plus-display-dwim)
    (define-key map (kbd "n") #'next-line)
    (define-key map (kbd "p") #'previous-line)
    (define-key map (kbd "TAB") #'ilist-plus-toggle-at-point)
    (define-key map (kbd "f") #'ilist-plus-toggle-fold-all)
    (define-key map (kbd "g") #'ilist-plus-refresh)
    (define-key map (kbd "q") #'ilist-plus-quit-window)
    (define-key map (kbd "s") #'ilist-plus-switch-sort)
    map)
  "Keymap of `ilist-plus-major-mode'.")

(define-derived-mode ilist-plus-major-mode special-mode "Ilist"
  "Major mode of the per-frame `*IListPlus[N]' outline buffers."
  (setq-local mode-line-format (or (ilist-plus--opt 'mode-line-format)
                                   (ilist-plus--build-mode-line-format)))
  ;; Wire in my custom highlight face.
  (setq-local face-remapping-alist '((hl-line ilist-plus-hl-face)))
  ;; High enough priority for this face so it takes precedence
  ;; unlike normal I don't want to preserve the underlying foreground color
  (setq-local hl-line-overlay-priority 10)
  ;; Setup the custom invisibility spec we use for folding.
  (add-to-invisibility-spec ilist-plus--invisible-spec)
  (setq-local line-move-ignore-invisible t)
  ;; Don't show a cursor in the Ilist window when it isn't the selected window.
  (setq-local cursor-in-non-selected-windows nil))

 ;;; Autofolding
(defvar-local ilist-plus-autofold-depth 2 "Initial depth to expand the ilist-plus window.")

;; Track whether we've shown this buffer's imenu-list at least once, and
;; if so, which containers were folded the last time we looked -- both
;; are buffer-local to the *source* buffer (not the shared *Ilist*
;; buffer), so each buffer remembers its own fold state independently.
(defvar-local ilist-plus--folded-once nil
  "Has `ilist-plus-fold-below-depth' folded this buffer's ilist-plus buffer.")

(defvar-local ilist-plus--folded-paths nil
  "Paths of the containers that were folded when this buffer was last shown.
Each path is an `ilist-plus--node-path'.  `ilist-plus--restore-folded-paths'
reapplies them whenever the Ilist is rebuilt for this buffer.")

(defun ilist-plus-fold-below-depth (&optional depth ibuf)
  "Collapse entries nested deeper than DEPTH in IBUF.
DEPTH defaults to `ilist-plus-autofold-depth' and IBUF to the current
Ilist buffer.  Top-level entries are depth 1."
  (interactive)
  (let ((depth (or depth ilist-plus-autofold-depth)))
    (with-current-buffer (or ibuf (ilist-plus--current-ibuf))
      (let* ((nodes (ilist-plus--build-nodes ilist-plus--entries))
             (n (length nodes)))
        (dotimes (i n)
          (let ((node (nth i nodes)))
            (when (and (ilist-plus--node-container-p node)
                       (= (ilist-plus--node-level node) depth))
              (let* ((end-i (ilist-plus--subtree-end nodes n i))
                     (span (ilist-plus--line-span n i end-i)))
                (ilist-plus--hide-region (car span) (cdr span))))))))))

(defun ilist-plus--path-prefix-p (prefix path)
  "Return if PREFIX equals PATH or is one of its ancestor paths."
  (cond ((null prefix) t)
        ((null path) nil)
        ((equal (car prefix) (car path))
         (ilist-plus--path-prefix-p (cdr prefix) (cdr path)))
        (t nil)))

(defun ilist-plus--remove-paths-with-prefix (prefix paths)
  "Return PATHS with PREFIX, and every path that has PREFIX as an
  ancestor, removed."
  (let (result)
    (dolist (path paths)
      (unless (ilist-plus--path-prefix-p prefix path)
        (push path result)))
    (nreverse result)))

(defun ilist-plus--update-folded-paths (fn)
  "Apply FN to the *source* buffer's saved `ilist-plus--folded-paths'
  and store the result back. FN receives the existing path list and
  returns the new one.

  Used by the fold commands to make a targeted, incremental edit to the
  saved fold snapshot, instead of rescanning every container's *current*
  visibility (as `ilist-plus--record-folded-paths' does). A full rescan
  is wrong here because it would also see -- and wrongly persist -- the
  temporarily unfolded state of whatever container
  `ilist-plus-reveal-current-entry' has un-hidden elsewhere in the tree,
  permanently forgetting that it should be folded again once point
  leaves it."
  (let ((src ilist-plus--source))
    (when (buffer-live-p src)
      (with-current-buffer src
        (setq ilist-plus--folded-paths (funcall fn ilist-plus--folded-paths))))))

(defun ilist-plus--fold-path (path)
  "Record PATH as folded in the saved snapshot."
  (ilist-plus--update-folded-paths
   (lambda (paths) (if (member path paths) paths (cons path paths)))))

(defun ilist-plus--unfold-path (path)
  "Remove PATH, and any of its descendant paths, from the saved
  snapshot -- unfolding a container also discards (removes the fold
							   overlays of) everything nested under it, so their paths shouldn't be
  restored as folded either."
  (ilist-plus--update-folded-paths
   (lambda (paths) (ilist-plus--remove-paths-with-prefix path paths))))

(defun ilist-plus--record-folded-paths (ilist)
  "Save the folded containers of the Ilist buffer ILIST on its source buffer.
Store their paths in `ilist-plus--folded-paths', so that
`ilist-plus--restore-folded-paths' can reapply them the next time the
Ilist is rebuilt, e.g. after switching buffers or after a reindex."
  (let ((src (buffer-local-value 'ilist-plus--source ilist)))
    (when (and ilist (buffer-live-p src))
      (let (folded)
        (with-current-buffer ilist
          (let* ((nodes (ilist-plus--build-nodes ilist-plus--entries))
                 (n (length nodes)))
            (dotimes (i n)
              (let ((node (nth i nodes)))
                (when (ilist-plus--node-container-p node)
                  (let* ((end-i (ilist-plus--subtree-end nodes n i))
                         (span (ilist-plus--line-span n i end-i)))
                    (when (ilist-plus--folded-p (car span))
                      (push (ilist-plus--node-path node) folded))))))))
        (with-current-buffer src
          (setq ilist-plus--folded-paths folded))))))

(defun ilist-plus--restore-folded-paths (paths)
  "Fold the containers of the current Ilist buffer whose path is in PATHS.
PATHS is a list as produced by `ilist-plus--record-folded-paths'.
Matching by name path rather than position lets folds survive a rebuild
even if entries shifted lines."
  (when paths
    (let* ((nodes (ilist-plus--build-nodes ilist-plus--entries))
           (n (length nodes)))
      (dotimes (i n)
        (let ((node (nth i nodes)))
          (when (and (ilist-plus--node-container-p node)
                     (member (ilist-plus--node-path node) paths))
            (let* ((end-i (ilist-plus--subtree-end nodes n i))
                   (span (ilist-plus--line-span n i end-i)))
              (ilist-plus--hide-region (car span) (cdr span)))))))))

(defun ilist-plus-fold-below-depth-once (ilist &optional depth)
  "The first time a buffer is shown in the Ilist buffer ILIST, apply the
  default depth-based fold; every time after, restore that buffer's own
  saved fold snapshot instead (see `ilist-plus--folded-paths'), then
  refresh fold markers. This runs with the *source* buffer as current, not
  ILIST -- so `ilist-plus--folded-once' and `ilist-plus--folded-paths' are
  read and written explicitly via ILIST's `ilist-plus--source' rather than
  relying on whatever happens to be current."
  (let ((src (buffer-local-value 'ilist-plus--source ilist)))
    (when (and ilist (buffer-live-p src))
      (with-current-buffer ilist
        (if (buffer-local-value 'ilist-plus--folded-once src)
            (ilist-plus--restore-folded-paths
             (buffer-local-value 'ilist-plus--folded-paths src))
          (ilist-plus-fold-below-depth depth ilist)
          (with-current-buffer src (setq ilist-plus--folded-once t))))
      (ilist-plus--record-folded-paths ilist)
      (ilist-plus-update-fold-markers ilist))))

(defun ilist-plus--relocate-hidden-highlight (beg end)
  "If the *Ilist* window's tracked highlight is currently sitting
  inside BEG..END -- a span this command just folded -- move it back
  to the line right before BEG (the container whose fold covered it,
				    always left visible) and refresh `hl-line-highlight' there.

  Without this, folding a section that contains the entry currently
  tracked from the *source* buffer leaves the highlight/window-point
  stranded on a now-invisible line: `ilist-plus-reveal-current-entry'
  (which would otherwise fix this up) only runs as part of
  `imenu-list-update', and `imenu-list-update' skips its own work
  whenever the *source* buffer's point hasn't moved since the last
  update -- which it hasn't, since this fold was triggered by
  interacting with the *Ilist* buffer directly, not by moving around
  in the source buffer."
  (let ((window (ilist-plus--window (current-buffer))))
    (when window
      (let ((pos (window-point window)))
        (when (and (>= pos beg) (< pos end))
          (set-window-point window (max (point-min) (1- beg)))
          (with-selected-window window
            (hl-line-highlight)))))))

(defun ilist-plus-fold-children (&optional depth)
  "Fold the entries DEPTH levels below the entry at point.
DEPTH defaults to 1, the entry's direct children.  Folding a child hides
its content, so the grandchildren disappear while the children stay
visible, just collapsed.  Any manual toggles within the subtree are
discarded and the rest of the tree is left untouched.  The subtree is
always reset to a fully shown state before it is refolded."
  (interactive)
  (let ((depth (or depth 1)))
    (with-current-buffer (ilist-plus--current-ibuf)
      (let* ((nodes (ilist-plus--build-nodes ilist-plus--entries))
             (n (length nodes))
             (start (1- (line-number-at-pos (point))))
             (base (nth start nodes))
             (target-level (+ (ilist-plus--node-level base) depth))
             (end (ilist-plus--subtree-end nodes n start)))
        (let ((span (ilist-plus--line-span n start end)))
          (ilist-plus--show-region (car span) (cdr span))
          (ilist-plus--unfold-path (ilist-plus--node-path base)))
        (let ((i (1+ start)))
          (while (< i end)
            (let ((node (nth i nodes)))
              (when (and (ilist-plus--node-container-p node)
                         (= (ilist-plus--node-level node) target-level))
                (let* ((sub-end (ilist-plus--subtree-end nodes n i))
                       (span (ilist-plus--line-span n i sub-end)))
                  (ilist-plus--hide-region (car span) (cdr span))
                  (ilist-plus--relocate-hidden-highlight (car span) (cdr span))
                  (ilist-plus--fold-path (ilist-plus--node-path node)))))
            (setq i (1+ i)))))))
  (ilist-plus-update-fold-markers))

(defun ilist-plus-toggle-at-point ()
  "Toggle folding of the container entry at point in the Ilist buffer.
Replaces hideshow's `hs-toggle-hiding' (formerly bound to TAB and \"f\")."
  (interactive)
  (with-current-buffer (ilist-plus--current-ibuf)
    (let* ((nodes (ilist-plus--build-nodes ilist-plus--entries))
           (n (length nodes))
           (start (1- (line-number-at-pos (point))))
           (node (nth start nodes)))
      (when (and node (ilist-plus--node-container-p node))
        (let* ((end (ilist-plus--subtree-end nodes n start))
               (span (ilist-plus--line-span n start end)))
          (if (ilist-plus--folded-p (car span))
              (progn
                (ilist-plus--show-region (car span) (cdr span))
                (ilist-plus--unfold-path (ilist-plus--node-path node)))
            (ilist-plus--hide-region (car span) (cdr span))
            (ilist-plus--relocate-hidden-highlight (car span) (cdr span))
            (ilist-plus--fold-path (ilist-plus--node-path node)))))))
  ;; A full marker refresh, not just the toggled line's -- `show-region'
  ;; removes every nested fold overlay in the span, so any child
  ;; containers that were folded need their own arrow flipped back to
  ;; expanded too.
  (ilist-plus-update-fold-markers))

(defun ilist-plus-toggle-fold-all ()
  "Toggle the whole *Ilist* buffer between fully unfolded and folded
  down to `ilist-plus-autofold-depth'. Bound to \"f\": if anything in the
  tree is currently folded, unfolds everything; otherwise refolds it
  back down to the autofold depth."
  (interactive)
  (with-current-buffer (ilist-plus--current-ibuf)
    (if (ilist-plus--any-folded-p)
        (progn
          (ilist-plus--show-region (point-min) (point-max))
          (ilist-plus--update-folded-paths (lambda (_) nil)))
      (ilist-plus-fold-below-depth)
      (ilist-plus--record-folded-paths (current-buffer))))
  (ilist-plus-update-fold-markers))


;; `ilist-plus--insert-entries' erases and rebuilds the whole Ilist buffer
;; whenever the source buffer's imenu entries actually change (e.g. a real
;; edit triggers a reindex, or the displayed buffer changed). That wipes
;; our fold overlays but `ilist-plus-fold-below-depth-once' (run from
;; `ilist-plus--update-inner' right after every update) recreates them
;; from `ilist-plus--folded-paths', so nothing extra is needed here.

;; TAB is a separate, keyboard-only concern: `button-map' (which
;; every button's `keymap' overlay property is `eq' to -- not a
;; per-button copy) binds TAB to `forward-button', and overlay
;; keymaps take priority over the buffer's local map, so
;; give *Ilist*'s buttons their own child
;; keymap (parented to `button-map', so RET/mouse-2 still work) with
;; just TAB overridden, and swap each button's `keymap' to point at
;; it. (No mouse bindings here -- clicking goes through the button's
;; own `follow-link'+`action' above, not through this keymap.)
(defvar ilist-plus-button-keymap
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map button-map)
    (define-key map (kbd "TAB") #'ilist-plus-toggle-at-point)
    map)
  "Like `button-map', but TAB toggles the *Ilist* fold instead of
  navigating between buttons.")

(defun ilist-plus--rebind-buttons ()
  "Point every button overlay in the *Ilist* buffer at
  `ilist-plus-button-keymap' instead of the shared global `button-map'.
  Idempotent -- cheap enough to call on every marker refresh."
  (dolist (ov (overlays-in (point-min) (point-max)))
    (when (and (overlay-get ov 'button)
               (eq (overlay-get ov 'keymap) button-map))
      (overlay-put ov 'keymap ilist-plus-button-keymap))))

;; Fold state is remembered per *source* buffer.  Reopening an Ilist starts every buffer over at the
;; default fold, except those still displayed by another frame's Ilist.
(defun ilist-plus-reset-fold-state (&optional except)
  "Forget every buffer's saved fold state, other than those in the list EXCEPT."
  (dolist (buf (buffer-list))
    (unless (memq buf except)
      (with-current-buffer buf
        (when (local-variable-p 'ilist-plus--folded-once)
          (setq ilist-plus--folded-once nil))
        (when (local-variable-p 'ilist-plus--folded-paths)
          (setq ilist-plus--folded-paths nil))))))

(defun ilist-plus--live-sources ()
  "Source buffers currently displayed by a visible Ilist window."
  (let (sources)
    (dolist (ibuf (ilist-plus--buffers))
      (when (ilist-plus--window ibuf)
        (push (buffer-local-value 'ilist-plus--source ibuf) sources)))
    (delq nil sources)))

;;; Updating

(defun ilist-plus--rescan-imenu ()
  "Force imenu to rescan the current buffer, applying the sort strategy."
  (setq imenu--index-alist nil)
  (imenu--make-index-alist)
  (ilist-plus-sort-advice))

;; Rescanning makes imenu walk the whole buffer for headings each time the Ilist updates, even
;; when nothing has changed since the last scan. Skip that for org buffers that haven't been
;; modified since we last collected entries, and reuse the previously generated tree.
(defvar-local ilist-plus--last-tick nil
  "`buffer-chars-modified-tick' as of the last imenu rescan for the Ilist.")

(defun ilist-plus--collect-entries (ibuf)
  "Index the current buffer into IBUF, the Ilist buffer to show it in.
  Signals `imenu-unavailable' when the buffer has no index."
  (unless (and (derived-mode-p 'org-mode)
               imenu--index-alist
               ilist-plus--last-tick
               (= ilist-plus--last-tick (buffer-chars-modified-tick)))
    (ilist-plus--rescan-imenu)
    (setq ilist-plus--last-tick (buffer-chars-modified-tick)))
  (let ((source (current-buffer))
        (entries imenu--index-alist))
    (with-current-buffer ibuf
      (unless (eq ilist-plus--source source)
        (force-mode-line-update))
      (setq ilist-plus--entries entries
            ilist-plus--source source))))

(defun ilist-plus--clear (ibuf)
  "Empty the Ilist buffer IBUF."
  (with-current-buffer ibuf
    (setq ilist-plus--entries nil
          ilist-plus--line-entries nil)
    (let ((inhibit-read-only t))
      (erase-buffer))))

(defun ilist-plus--position-translator ()
  "A function turning an imenu position of this buffer into a buffer position."
  (cond
   ((and (ilist-plus--opt 'custom-position-translator)
         (funcall (ilist-plus--opt 'custom-position-translator))))
   ;; semantic uses overlays, return the overlay's start as position
   ((or (eq imenu-create-index-function 'semantic-create-imenu-index)
        (and (eq imenu-create-index-function
                 'spacemacs/python-imenu-create-index-python-or-semantic)
             (bound-and-true-p semantic-mode)))
    #'overlay-start)
   ;; An array position was created by `eglot-imenu'; anything else by the default indexer.
   ((and (fboundp #'eglot-managed-p) (eglot-managed-p))
    (lambda (pos)
      (if (arrayp pos)
          (eglot--lsp-position-to-point (plist-get (plist-get (aref pos 0) :range) :start) t)
        pos)))
   (t #'identity)))

;; `ilist-plus--current-entry' skips subalist (container) entries when deciding which line to
;; highlight, since a plain subalist cons has no position of its own. But `org-imenu-get-tree'
;; still stamps each entry's *name* string with an `org-imenu-marker' text property pointing at
;; that heading's own position, even for headings that end up container-only (i.e. any heading with
;; a child heading, like "IMenu" in tour.org). Recover that so point-in-container also highlights
;; the container's own line instead of falling back to the previous sibling.
(defun ilist-plus--entry-position (entry)
  "Return a comparable buffer position for ENTRY, or nil if none exists."
  (if (imenu--subalist-p entry)
      (get-text-property 0 'org-imenu-marker (car entry))
    (funcall (ilist-plus--position-translator)
             (if (listp (cdr entry)) (cadr entry) (cdr entry)))))

(defun ilist-plus--current-entry (line-entries)
  "The entry of LINE-ENTRIES that point in the current (source) buffer is in."
  (let ((point-pos (point-marker))
        (offset (point-min-marker))
        match-entry)
    (dolist (entry line-entries match-entry)
      (let ((entry-pos (ilist-plus--entry-position entry)))
        (when (and entry-pos (<= offset entry-pos point-pos))
          (setq offset entry-pos)
          (setq match-entry entry))))))

(defun ilist-plus--show-current-entry (ibuf)
  "Move IBUF's window point to the entry the current (source) buffer's point is in."
  (let ((window (ilist-plus--window ibuf)))
    (when window
      (let* ((line-entries (buffer-local-value 'ilist-plus--line-entries ibuf))
             (line (cl-position (ilist-plus--current-entry line-entries)
                                line-entries :test #'equal)))
        (with-selected-window window
          (goto-char (point-min))
          (forward-line (or line 0))
          (hl-line-mode 1))))))

(defun ilist-plus--resize-window (ibuf)
  "Fit IBUF's window to its content."
  (when (buffer-local-value 'ilist-plus--line-entries ibuf)
    (let ((fit-window-to-buffer-horizontally t))
      (dolist (window (get-buffer-window-list ibuf nil t))
        (fit-window-to-buffer window)))))

;; When the tracked entry is inside a currently-folded block, temporarily unfold whatever hides it
;; (even several containers deep) so the actual entry line is visible and highlighted, instead of
;; just moving the highlight up to the nearest visible ancestor header. The overlays we delete below
;; are never recorded into `ilist-plus--folded-paths', so they are recreated when folding is
;; reapplied when moving entries.
(defun ilist-plus-reveal-current-entry (ibuf)
  "Unfold whatever hides the tracked entry in IBUF's window and highlight it."
  (let ((window (ilist-plus--window ibuf)))
    (when window
      (let ((pos (window-point window))
            (revealed nil))
        (with-current-buffer ibuf
          (dolist (ov (overlays-at pos))
            (when (overlay-get ov 'ilist-plus-fold)
              (delete-overlay ov)
              (setq revealed t))))
        (when revealed
          (ilist-plus-update-fold-markers ibuf))
        (with-selected-window window
          (hl-line-highlight))))))

(defun ilist-plus--update-inner (ibuf force)
  "Update the Ilist buffer IBUF from the current (source) buffer's point.
FORCE will always do an update even if nothing has changed."
  (catch 'index-failure
    (let ((old-entries (buffer-local-value 'ilist-plus--entries ibuf))
          (last-location (buffer-local-value 'ilist-plus--last-location ibuf))
          (location (point-marker)))
      ;; don't update if `point' didn't move
      (unless (and (null force)
                   last-location
                   (eq (marker-buffer last-location) (current-buffer))
                   (= location last-location))
        (with-current-buffer ibuf
          (setq ilist-plus--last-location location))
        (condition-case nil
            (ilist-plus--collect-entries ibuf)
          (imenu-unavailable
           (if (ilist-plus--opt 'persist-when-imenu-index-unavailable)
               (throw 'index-failure nil)
             (ilist-plus--clear ibuf))))
        (when (or force
                  (not (equal old-entries (buffer-local-value 'ilist-plus--entries ibuf))))
          (with-current-buffer ibuf
            (ilist-plus--insert-entries)))
        (when (ilist-plus--opt 'update-current-entry)
          (ilist-plus--show-current-entry ibuf))
        (when (ilist-plus--opt 'auto-resize)
          (ilist-plus--resize-window ibuf))
        ;; We have to fold before highlighting.
        (ilist-plus-fold-below-depth-once ibuf)
        (ilist-plus-highlight-modified-entries ibuf)
        (ilist-plus--run-hooks 'update-hook)
        (ilist-plus-reveal-current-entry ibuf)
        nil))))

(defun ilist-plus-update (&optional force frame source)
  "Update FRAME's (default: the selected frame's) Ilist buffer.
  The outline is built from SOURCE, or by default from the buffer shown in
  FRAME's selected window; nothing happens when that is an Ilist buffer
  itself.  Unless FORCE is non-nil, nothing happens either when point
  hasn't moved since the last update."
  (let* ((frame (or frame (selected-frame)))
         (ibuf (ilist-plus--buffer frame)))
    (when (and ibuf (frame-live-p frame))
      (let* ((window (frame-selected-window frame))
             (src (or source (window-buffer window)))
             (pos (if source
                      (with-current-buffer source (point))
                    (window-point window))))
        (when (and (buffer-live-p src)
                   (not (ilist-plus--ilist-buffer-p src)))
          (with-current-buffer src
            (save-excursion
              (goto-char pos)
              (ilist-plus--update-inner ibuf force))))))))

(defun ilist-plus--refresh (ibuf)
  "Rebuild the Ilist buffer IBUF from its source buffer."
  (let ((src (buffer-local-value 'ilist-plus--source ibuf))
        (frame (buffer-local-value 'ilist-plus--frame ibuf)))
    (when (and (buffer-live-p src) (frame-live-p frame))
      (ilist-plus-update t frame src))))

(defun ilist-plus-refresh ()
  "Refresh the current frame's Ilist."
  (interactive)
  (ilist-plus--refresh (ilist-plus--current-ibuf)))

;;; Timer

;; One idle timer serves every frame: each visible Ilist is updated from its own frame's
;; selected window.  It stops itself once no Ilist window is left.
(defvar ilist-plus--timer nil)

(defun ilist-plus--stop-timer ()
  (when ilist-plus--timer
    (cancel-timer ilist-plus--timer)
    (setq ilist-plus--timer nil)))

(defun ilist-plus--update-all ()
  (let (any)
    (dolist (ibuf (ilist-plus--buffers))
      (let ((frame (buffer-local-value 'ilist-plus--frame ibuf)))
        (when (and (frame-live-p frame) (get-buffer-window ibuf frame))
          (setq any t)
          (ilist-plus-update nil frame))))
    (unless any
      (ilist-plus--stop-timer))))

(defun ilist-plus--start-timer ()
  (when (and (ilist-plus--opt 'auto-update) (not ilist-plus--timer))
    (setq ilist-plus--timer
          (run-with-idle-timer (ilist-plus--opt 'idle-update-delay) t #'ilist-plus--update-all))))

;;; Display and toggle

(defun ilist-plus--split-size ()
  "The size argument for `split-window' from `ilist-plus-size'."
  (let ((size (ilist-plus--opt 'size))
        (frame-size (if (memq (ilist-plus--opt 'position) '(left right))
                        (frame-width)
                      (frame-height))))
    (if (integerp size)
        (- size)
      (- (round (* frame-size size))))))

(defun ilist-plus--display-buffer (buffer alist)
  "`display-buffer' action showing BUFFER in a side window of the selected frame."
  (or (get-buffer-window buffer)
      (let ((window (split-window (frame-root-window) (ilist-plus--split-size)
                                  (ilist-plus--opt 'position))))
        (window--display-buffer buffer window 'window alist)
        (set-window-dedicated-p window t)
        window)))

(defun ilist-plus--open ()
  "Show the selected frame's Ilist, built from the current buffer."
  (let ((source (current-buffer))
        (ibuf (ilist-plus--get-buffer)))
    (ilist-plus-reset-fold-state (ilist-plus--live-sources))
    (ilist-plus--start-timer)
    (if (ilist-plus--opt 'focus-after-activation)
        (pop-to-buffer ibuf '(ilist-plus--display-buffer))
      (display-buffer ibuf '(ilist-plus--display-buffer)))
    (ilist-plus-update t (selected-frame) source)))

(defun ilist-plus--close (&optional frame)
  "Hide FRAME's (default: the selected frame's) Ilist."
  (let* ((frame (or frame (selected-frame)))
         (ibuf (ilist-plus--buffer frame)))
    (when ibuf
      (ignore-errors (quit-windows-on ibuf nil frame))
      (bury-buffer ibuf))
    (unless (cl-some #'ilist-plus--window (ilist-plus--buffers))
      (ilist-plus--stop-timer))))

;;;###autoload
(defun ilist-plus-toggle ()
  "Show or hide the Ilist of the selected frame, leaving other frames' alone."
  (interactive)
  (let ((ibuf (ilist-plus--buffer)))
    (if (and ibuf (get-buffer-window ibuf))
        (ilist-plus--close)
      (ilist-plus--open))))

(defun ilist-plus-quit-window ()
  "Hide this Ilist's window."
  (interactive)
  (ilist-plus--close (buffer-local-value 'ilist-plus--frame (ilist-plus--current-ibuf))))

;;; Jumping to entries

(defun ilist-plus--find-entry ()
  "The entry on the current line of an Ilist buffer."
  (nth (1- (line-number-at-pos)) ilist-plus--line-entries))

(defun ilist-plus--goto-entry (entry)
  "Jump to ENTRY in the source buffer of the current Ilist buffer."
  (let ((ibuf (current-buffer))
        (source ilist-plus--source)
        (frame ilist-plus--frame))
    (unless (buffer-live-p source)
      (user-error "The buffer this Ilist was built from is gone"))
    (let ((window (get-buffer-window source frame)))
      (if window
          (select-window window)
        (pop-to-buffer source)))
    (imenu entry)
    (ilist-plus--run-hooks 'after-jump-hook)
    (ilist-plus--show-current-entry ibuf)))

(defun ilist-plus-goto-entry ()
  "Switch to the source buffer and show the entry on this line."
  (interactive)
  (ilist-plus--goto-entry (ilist-plus--find-entry)))

(defun ilist-plus-ret-dwim ()
  "Jump to or fold the entry at point."
  (interactive)
  (let ((entry (ilist-plus--find-entry)))
    (if (imenu--subalist-p entry)
        (ilist-plus-toggle-at-point)
      (ilist-plus--goto-entry entry))))

(defun ilist-plus-display-dwim ()
  "Show or fold the entry at point without leaving the Ilist window."
  (interactive)
  (save-selected-window
    (ilist-plus-ret-dwim)))

;;; Hierarchical treesitter tree parsing

;; Generate a marker for the given node
;; This can only be done while in the buffer
(defun ilist-plus-make-marker (buffer point)
  (with-current-buffer buffer
    (copy-marker point)))

;; treesit is built in post version 29.
(require 'treesit)

;; Treesitter node name function for most node types
(defun ilist-plus-get-def-name (node)
  (treesit-node-text
   (treesit-node-child-by-field-name node "name") t))

;; Treesitter node name function for class fields
(defun ilist-plus-get-field-name (node)
  (treesit-node-text
   (treesit-node-child-by-field-name (treesit-node-child-by-field-name node "declarator") "name") t))

;; Simple wrapper to make an imenu leaf from a treesitter node
(defun ilist-plus-leaf (node buffer name-func)
  (cons (funcall name-func node)
        (ilist-plus-make-marker buffer (treesit-node-start node))))

;; Compare two imenu nodes
(defun ilist-plus-compare (left right)
  (string-lessp (car left) (car right)))

;; Buffer-local sort/grouping strategy, set via `ilist-plus-switch-sort' and
;; multiplexed on by `ilist-plus-sort-advice' and, for the elisp indexer,
;; `ilist-plus-elisp-index' itself. One of:
;;   nil (or 'position) -- the default: whatever order/structure the
;;     create-index-function naturally produces (physical position, nested
;;     under headers for elisp).
;;   'alphabetical -- `ilist-plus-sort-alphabetically' post-processes
;;     whatever structure the create-index-function produced.
;;   'by-type -- elisp-only: `ilist-plus-elisp-index' skips header nesting
;;     entirely and groups flatly by raw imenu category instead.
(defvar-local ilist-plus-sort-strategy nil)

;; String for which sorting mode we're in for use in the mode-line
(defun ilist-plus-current-sort (&optional buffer)
  (let ((strategy (if buffer
                      (buffer-local-value 'ilist-plus-sort-strategy buffer)
                    ilist-plus-sort-strategy)))
    (cond ((eq strategy 'alphabetical) "alpha")
          ((eq strategy 'by-type) "by-type")
          (t "pos"))))

;; Multiplexer advice that post-sorts alphabetically when that strategy is
;; selected. `by-type' is handled structurally by `ilist-plus-elisp-index'
;; instead, and plain position order needs no override.
(defun ilist-plus-sort-advice ()
  (when (eq ilist-plus-sort-strategy 'alphabetical)
    (setq imenu--index-alist (ilist-plus-sort-alphabetically))))

;; Custom sorting function that alphabetizes per imenu object type.  There is no built in facility
;; to extend sorting so we have to wire this in via advice This is written generically to handle
;; elisp which just inserts all the functions as leaf nodes and java lsp/treesitter which insert
;; everything under categories.
(defun ilist-plus-sort-alphabetically ()
  (interactive)
  (let ((entries imenu--index-alist)
        (leaf-entries nil)
        (sorted-entries nil))

    (dolist (entry entries)

      ;; if its a category container sort the entries within it
      ;; o/w add to a temp list to be sorted below
      (if (not (listp (cdr entry)))
          (setq leaf-entries (cons entry leaf-entries))
        (let* ((objects (cdr entry))
               (type (car entry))
               (sorted-objects (sort objects
                                     (lambda (left right)
                                       (string-lessp (car left) (car right))))))

          (setq sorted-entries (append sorted-entries (list (cons type sorted-objects))))
          )))

    ;; Sort the top level leaf entries
    (setq sorted-entries (append sorted-entries
				 (sort leaf-entries
				       (lambda (left right)
					 (string-lessp (car left) (car right))))))
    ))

;; Interactive command to make it easy to swap how the symbols are sorted
;; Note: default is to go by position so we don't have to override for that.
;; "by type" is elisp-only (see `ilist-plus-elisp-index-by-type'); harmless
;; but pointless for treesitter, which is already grouped by type
;; regardless of strategy, so it's only offered there.
(defun ilist-plus-switch-sort (strategy)
  (interactive
   (with-current-buffer (buffer-local-value 'ilist-plus--source (ilist-plus--current-ibuf))
     (unless (memq imenu-create-index-function '(ilist-plus-java-ts-index ilist-plus-elisp-index))
       (user-error "Sort switching is only available for treesitter or elisp imenus"))
     (let ((choices (append '(("alphabetical" . alphabetical)
                              ("by position" . position))
                            (when (eq imenu-create-index-function 'ilist-plus-elisp-index)
                              '(("by type" . by-type))))))
       (list (alist-get
	      (completing-read "Choose: " choices)
	      choices nil nil 'equal)))))
  (let ((ibuf (ilist-plus--current-ibuf)))
    (with-current-buffer (buffer-local-value 'ilist-plus--source ibuf)
      (setq-local ilist-plus-sort-strategy (unless (eq strategy 'position) strategy))
      ;; mode line update to add the sort message.
      (force-mode-line-update))
    (ilist-plus--refresh ibuf)))

(defun ilist-plus-cycle-sort (event)
  "Switch the sort order of the Ilist clicked in EVENT to the next available one."
  (interactive "e")
  (with-current-buffer (window-buffer (posn-window (event-start event)))
    (let* ((src ilist-plus--source)
           (choices (with-current-buffer src
                      (unless (memq imenu-create-index-function
                                    '(ilist-plus-java-ts-index ilist-plus-elisp-index))
                        (user-error "Sort switching is only available for treesitter or elisp imenus"))
                      (append '(position alphabetical)
                              (when (eq imenu-create-index-function 'ilist-plus-elisp-index)
                                '(by-type)))))
           (current (or (buffer-local-value 'ilist-plus-sort-strategy src) 'position)))
      (ilist-plus-switch-sort (or (cadr (memq current choices)) (car choices))))))

;; Guard the java-ts indexer and its helpers the same way as the treesit
;; node-name helpers above: only defined when `treesit' is available.
(when (require 'treesit nil t)

  ;; Sort a list of imenu nodes
  (defun ilist-plus-sort (seq)
    (sort seq 'ilist-plus-compare))

  ;; Walk the parent node class of an interface, class or enum and
  ;; construct a list of all fields, constructors and methods.
  ;; Recursion occurs when there is an inner class.
  ;; predeclare so byte compiling is happy.
  (declare-function ilist-plus-walk-object-declaration ilist-plus.el)
  (defun ilist-plus-walk-object-declaration (classnode buffer)
    (let ((constructors ())
          (fields ())
          (methods ())
          (inner-classes ())
          (result ())
          (orderfn (if (eq ilist-plus-sort-strategy 'alphabetical) 'ilist-plus-sort 'reverse)))
      (dolist (node (treesit-node-children classnode))
        (progn
          (cond ((equal (treesit-node-type node) "constructor_declaration")
                 (push (ilist-plus-leaf node buffer 'ilist-plus-get-def-name) constructors))

                ((equal (treesit-node-type node) "method_declaration")
                 (push (ilist-plus-leaf node buffer 'ilist-plus-get-def-name) methods))

                ((equal (treesit-node-type node) "class_declaration")
                 (let* ((body (treesit-node-child-by-field-name node "body"))
                        (classname (ilist-plus-get-def-name node))
			(subleafs (cons (cons "declaration" (ilist-plus-make-marker buffer (treesit-node-start node)))
					(ilist-plus-walk-object-declaration body buffer))))

                   (push (cons classname subleafs) inner-classes)))

                ((equal (treesit-node-type node) "field_declaration")
                 (push (ilist-plus-leaf node buffer 'ilist-plus-get-field-name) fields)))))

      (when inner-classes (push (cons "Inner Classes" (funcall orderfn inner-classes)) result))
      (when methods (push (cons "Methods" (funcall orderfn methods)) result))
      (when fields (push (cons "Fields" (funcall orderfn fields)) result))
      (when constructors (push (cons "Constructors" (funcall orderfn constructors)) result))
      ;; final value
      result))

  ;; Main routine that walks top level of the grammar tree and constructs imenu nodes
  ;; to turn on - (setq imenu-create-index-function 'ilist-plus-java-ts-index)
  (defun ilist-plus-java-ts-index (&optional buffer)
    (interactive)
    (unless buffer (setq buffer (current-buffer)))
    (with-current-buffer (if buffer (get-buffer buffer) (current-buffer))
      (let ((classes '())
            (interfaces '())
            (enums '())
            (subresults '())
            (result '()))

        (dolist (node (treesit-node-children (treesit-buffer-root-node)))
          (let ((type (treesit-node-type node)))
            (when (or (equal type "class_declaration")
                      (equal type "interface_declaration")
                      (equal type "enum_declaration"))
              (let* ((body (treesit-node-child-by-field-name node "body"))
                     (subleafs  (when body (ilist-plus-walk-object-declaration body buffer)))
                     (objectname (ilist-plus-get-def-name node))
                     (object-start (treesit-node-start node)))

                (push (cons "declaration" (ilist-plus-make-marker buffer object-start)) subleafs)
                (unless (assoc type subresults) (push (cons type nil) subresults))
                (push (cons objectname subleafs) (cdr (assoc type subresults)))

                (cond ((equal type "class_declaration")
                       (push (cons objectname subleafs) classes))
                      ((equal type "enum_declaration")
                       (push (cons objectname subleafs) enums))
                      ((equal type "interface_declaration")
                       (push (cons objectname subleafs) interfaces)))))))

        (when enums (push (cons "Enums" (reverse enums)) result))
        (when (assoc "class_declaration" subresults)
          (push (cons "Classes" (reverse (cdr (assoc "class_declaration" subresults)))) result))
        (when interfaces (push (cons "Interfaces" (reverse interfaces)) result))
        result))))

;;; Elisp custom header handling

;; Add additional expressions to baseline parsing in an elisp hook.  This has to
;; be done after elisp loads each time.  `ilist-plus-elisp-index-by-position'
;; relies on these entries being present in `imenu-generic-expression'.
(defun ilist-plus--elisp-mode-setup ()
  (add-to-list 'imenu-generic-expression
               (list "Use-package"
                     (concat "^\\s-*(use-package\\s-+\\("
                             lisp-mode-symbol-regexp "\\)")
                     1))

  (add-to-list 'imenu-generic-expression
               '("Sections" "^;;;\\s-+\\(.*\\)$" 1))

  (add-to-list 'imenu-generic-expression
	       '("Subsections" "^;;;;\\s-+\\(.*\\)$" 1)))

;; fold `defun'/`use-package' entries under the ";;; Section" comment
;; header they're physically located under.

;; Every leaf (NAME . MARKER) cons across all of RAW's category groups
;; (cdr is a list, e.g. "Sections"/"Types"/"Variables"/"Use-package") and
;; ungrouped entries (cdr is a marker, e.g. plain functions), flattened
;; into one list, any order. RAW is `imenu--generic-function''s direct
;; output.
(defun ilist-plus-elisp-flatten-raw (raw)
  (let (leaves)
    (dolist (entry raw)
      (if (listp (cdr entry))
          (dolist (leaf (cdr entry)) (push leaf leaves))
        (push entry leaves)))
    leaves))

;; Back POS up over contiguous comment-only/blank lines immediately
;; preceding it in BUFFER, never crossing below FLOOR (the previous
;; entry's own raw position in adjacency order) -- a `diff-hl' hunk
;; touching a doc-comment that introduces an entry should count as a
;; change to THAT entry, not to whichever entry happens to sort right
;; before it, since the comment lines themselves aren't separately
;; indexed. FLOOR stops the backward walk from swallowing a line that
;; already belongs to the previous entry.
(defun ilist-plus-elisp-back-over-comments (pos buffer floor)
  (with-current-buffer buffer
    (save-excursion
      ;; Compare whole-line boundaries, not raw positions: FLOOR usually
      ;; falls mid-line (it's another entry's own match position, e.g. at
      ;; a defun's NAME, not its line start), but for `^'-anchored
      ;; patterns like "Sections" it lands right at that line's own
      ;; beginning -- in which case a raw `>=' comparison would let the
      ;; walk step onto and swallow FLOOR's entire line as if it were
      ;; just an anonymous leading comment, when it's actually the
      ;; previous entry's own exclusive territory.
      (let ((floor-bol (progn (goto-char floor) (line-beginning-position))))
        (goto-char pos)
        (beginning-of-line)
        (let ((start (point)))
          (while (and (> (point) floor-bol)
		      (progn (forward-line -1)
                             (and (> (point) floor-bol)
                                  (looking-at "^[ \t]*\\(;.*\\)?$"))))
            (setq start (point)))
          start)))))

;; Buffer-local table (in the SOURCE buffer, i.e. the elisp buffer being
;; indexed, not the *Ilist* buffer) mapping every leaf's raw, normalized
;; buffer position to its true (BEG . END) span, as computed once by
;; `ilist-plus-elisp-parse-and-tag-ranges'. `ilist-plus--entry-range'
;; reads this to answer is a diff-hl hunk inside this entry's span
(defvar-local ilist-plus--range-table nil)

;; Call `imenu--generic-function' in the current buffer and populate
;; `ilist-plus--range-table' with every resulting leaf's true (BEG
;; . END) span -- BEG backed up over its own leading comment (see
;; `ilist-plus-elisp-back-over-comments'), END the very next entry's
;; (equally backed-up) start anywhere in the buffer, across every
;; category including "Sections"/"Subsections", or `point-max' for the
;; physically last entry. Computed once here, from true physical
;; adjacency across ALL entries regardless of category, before any
;; mode-specific bucketing/nesting/sorting.
;;
;; Keyed by each entry's own RAW position
;; (not its backed-up BEG), normalized to a plain integer since two
;; distinct marker objects at the same buffer position are not `eql' --
;; this is also what makes the table double as a lookup for the
;; synthetic "" declaration leaf `ilist-plus-elisp-build-header' fabricates
;; for a Section/Subsection header (a fresh cons with no property of its
;; own, but pointing at the same raw position the header's own leaf in
;; RAW was keyed under). Returns RAW, for the caller to bucket/nest as
;; before.
(defun ilist-plus-elisp-parse-and-tag-ranges ()
  (let* ((raw (imenu--generic-function imenu-generic-expression))
         (leaves (sort (ilist-plus-elisp-flatten-raw raw)
		       (lambda (a b) (< (cdr a) (cdr b)))))
         (buf (current-buffer))
         (table (make-hash-table :test 'eql))
         (floor (point-min))
         (rest leaves)
         starts)
    (while rest
      (let ((s (ilist-plus-elisp-back-over-comments (cdar rest) buf floor)))
        (push s starts)
        (setq floor (cdar rest)))
      (setq rest (cdr rest)))
    (setq starts (nreverse starts))
    (let ((ls leaves) (ss starts))
      (while ls
        (let* ((entry (car ls))
	       (key (let ((p (cdr entry))) (if (markerp p) (marker-position p) p)))
	       (beg (car ss))
	       (end (if (cdr ss) (cadr ss) (point-max))))
          (puthash key (cons beg end) table))
        (setq ls (cdr ls) ss (cdr ss))))
    (setq-local ilist-plus--range-table table)
    raw))

;; (NAME BEG END) for each entry in ENTRIES (an alist of (name . marker),
;; already sorted by position), covering from the entry's own marker up to
;; the next entry's marker, or point-max for the last one.
(defun ilist-plus-elisp-ranges (entries)
  (let (ranges)
    (while entries
      (push (list (caar entries) (cdar entries)
                  (if (cadr entries) (cdadr entries) (point-max)))
            ranges)
      (setq entries (cdr entries)))
    (nreverse ranges)))

;; Name of the range in RANGES that POS falls inside, or nil
;; if POS precedes the first range (or there are no ranges at all).
(defun ilist-plus-elisp-find-section (ranges pos)
  (catch 'found
    (dolist (range ranges)
      (when (and (>= pos (nth 1 range)) (< pos (nth 2 range)))
        (throw 'found (nth 0 range))))))

;; Bucket ENTRIES (an alist of (name . marker), sorted ascending by
;; position) into RANGES by `ilist-plus-elisp-find-section', returning
;; (BUCKETS . ORPHANS): BUCKETS is a hash table of range name -> entries
;; (ascending), ORPHANS the entries (ascending) that precede every range.
(defun ilist-plus-elisp-bucket-by-section (entries ranges)
  (let ((buckets (make-hash-table :test 'equal))
        (orphans nil))
    (dolist (entry entries)
      (let ((section (ilist-plus-elisp-find-section ranges (cdr entry))))
        (if section
            (puthash section (cons entry (gethash section buckets)) buckets)
          (push entry orphans))))
    (maphash (lambda (k v) (puthash k (nreverse v) buckets)) buckets)
    (cons buckets (nreverse orphans))))

;; If one of SECTIONS is named "Code" (the ";;; Code:" boilerplate header
;; conventional in Elisp files), nest every section that follows it
;; underneath it instead of leaving them as top-level siblings, since
;; everything after ";;; Code:" belongs to "the code" rather than being a
;; peer of Commentary/Code/etc.
(defun ilist-plus-elisp-nest-under-code (sections)
  (let ((rest sections) before)
    (catch 'done
      (while rest
        (if (equal (caar rest) "Code:")
            (throw 'done (append (nreverse before)
                                 (list (cons "Code" (append (cdar rest) (cdr rest))))))
          (push (car rest) before)
          (setq rest (cdr rest))))
      sections)))

;; Build a nested imenu alist entry for a header named NAME at buffer
;; position START, with CHILDREN (already-built nested entries, if any --
;; used to nest a Section's Subsections underneath it) inserted before
;; header's own Use-package/function/other-category entries.
;; CATEGORY-BUCKETS is an alist of (CATEGORY-NAME . HASH-TABLE), one entry
;; per non-function, non-Use-package category (Variables/Types/...), each
;; HASH-TABLE mapping a header NAME to that category's entries physically
;; inside it -- same shape as FN-BUCKETS/PKG-BUCKETS.
(defun ilist-plus-elisp-build-header (name start fn-buckets pkg-buckets category-buckets &optional children)
  (let ((fns (gethash name fn-buckets))
        (pkgs (gethash name pkg-buckets)))
    (cons name (append (list (cons "" start))
		       (when pkgs (list (cons "Use-package" pkgs)))
		       (delq nil (mapcar (lambda (cb)
                                           (let ((entries (gethash name (cdr cb))))
                                             (when entries (cons (car cb) entries))))
                                         category-buckets))
		       fns
		       children))))

;; Custom imenu-create-index-function for emacs-lisp-mode, dispatching on
;; `ilist-plus-sort-strategy' between the header-nested view (the
;; default) and the flat by-type view.
(defun ilist-plus-elisp-index ()
  (if (eq ilist-plus-sort-strategy 'by-type)
      (ilist-plus-elisp-index-by-type)
    (ilist-plus-elisp-index-by-position)))

;; Regroup the basic indexed nodes under a "Sections" header they fll under.
;; "Subsections" (";;;; " headers) also nest under whichever "Sections" (";;; ")
;; header they physically fall inside. Every section/subsection also gets
;; a leading "." entry jumping to its own header (mirroring the
;; "declaration" entry `ilist-plus-walk-object-declaration' adds for a class), so
;; one with no other content is still navigable.
(defun ilist-plus-elisp-index-by-position ()
  (let ((raw (ilist-plus-elisp-parse-and-tag-ranges))
        sections subsections usepkg categories functions)
    (dolist (entry raw)
      (cond ((equal (car entry) "Sections") (setq sections (cdr entry)))
            ((equal (car entry) "Subsections") (setq subsections (cdr entry)))
            ((equal (car entry) "Use-package") (setq usepkg (cdr entry)))
            ((listp (cdr entry)) (push entry categories))
            (t (push entry functions))))
    (setq categories (nreverse categories))
    (setq functions (sort functions (lambda (left right) (< (cdr left) (cdr right)))))
    (setq usepkg (sort usepkg (lambda (left right) (< (cdr left) (cdr right)))))
    (setq subsections (sort subsections (lambda (left right) (< (cdr left) (cdr right)))))
    (let* ((section-ranges (ilist-plus-elisp-ranges sections))
           ;; `sort' on a list is destructive so use `copy-sequence' gives the merge its own cells.
           (fine-ranges (ilist-plus-elisp-ranges
                         (sort (copy-sequence (append sections subsections))
			       (lambda (left right) (< (cdr left) (cdr right))))))
           (fn-bucketed (ilist-plus-elisp-bucket-by-section functions fine-ranges))
           (pkg-bucketed (ilist-plus-elisp-bucket-by-section usepkg fine-ranges))
           ;; One (buckets . orphans) pair per other category, same shape
           ;; as PKG-BUCKETED.
           (category-bucketed
            (mapcar (lambda (cat)
		      (cons (car cat) (ilist-plus-elisp-bucket-by-section (cdr cat) fine-ranges)))
                    categories))
           ;; ...but a Subsection's *parent* is decided against Sections
           ;; alone, since a Subsection always nests directly under the
           ;; Section it physically falls inside, regardless of any
           ;; intervening Subsection siblings.
           (sub-bucketed (ilist-plus-elisp-bucket-by-section subsections section-ranges))
           (fn-buckets (car fn-bucketed))
           (pkg-buckets (car pkg-bucketed))
           (sub-buckets (car sub-bucketed))
           (pkg-orphans (cdr pkg-bucketed))
           (sub-orphans (cdr sub-bucketed))
           (category-buckets (mapcar (lambda (c) (cons (car c) (car (cdr c)))) category-bucketed))
           ;; Members of an other-category that precede every section --
           ;; these have nothing to nest under, so they stay flat
           ;; top-level siblings, same as PKG-ORPHANS.
           (category-orphans (delq nil (mapcar (lambda (c)
                                                 (let ((orphans (cdr (cdr c))))
                                                   (when orphans (cons (car c) orphans))))
					       category-bucketed))))
      (append (ilist-plus-elisp-nest-under-code
	       (mapcar (lambda (range)
                         (ilist-plus-elisp-build-header
                          (car range) (nth 1 range) fn-buckets pkg-buckets category-buckets
                          (mapcar (lambda (sub)
                                    (ilist-plus-elisp-build-header
                                     (car sub) (cdr sub) fn-buckets pkg-buckets category-buckets))
                                  (gethash (car range) sub-buckets))))
		       section-ranges))
	      (when pkg-orphans (list (cons "Use-package" pkg-orphans)))
	      category-orphans
	      (mapcar (lambda (sub)
                        (ilist-plus-elisp-build-header (car sub) (cdr sub) fn-buckets pkg-buckets category-buckets))
		      sub-orphans)
	      (cdr fn-bucketed)))))

;; Flat by-type view: no header nesting at all -- every category
;; (Functions/Use-package/Variables/Types/...) becomes its own top-level
;; group, sorted by position within. "Sections"/"Subsections" are dropped
;; rather than shown as an empty-feeling category, since they're purely a
;; structural device for the by-position view, not content in their own
;; right.
(defun ilist-plus-elisp-index-by-type ()
  (let ((raw (ilist-plus-elisp-parse-and-tag-ranges))
        categories functions)
    (dolist (entry raw)
      (cond ((equal (car entry) "Sections") nil)
            ((equal (car entry) "Subsections") nil)
            ((listp (cdr entry)) (push entry categories))
            (t (push entry functions))))
    (setq categories (nreverse categories))
    (append (when functions
	      (list (cons "Functions"
                          (sort functions (lambda (left right) (< (cdr left) (cdr right)))))))
            (mapcar (lambda (cat)
		      (cons (car cat)
                            (sort (copy-sequence (cdr cat))
                                  (lambda (left right) (< (cdr left) (cdr right))))))
                    categories))))

;;; VC Highlighting

;; Highlight imenu entries whose corresponding source section has an
;; uncommitted VC change, per `diff-hl' hunk overlays (each hunk gets one
;; overlay spanning its changed lines, tagged with the `diff-hl-hunk'
;; property).

(defface ilist-plus-modified-face
  `((t (:inherit ilist-plus-face :background ,(ilist-plus--modus-color 'bg-changed nil "yellow"))))
  "Face for imenu-list entries covering a source section with a
pending `diff-hl' change."
  :group 'ilist-plus)

(defun ilist-plus--modus-apply-heading-colors ()
  "Set `ilist-plus-entry-face-N' foregrounds to the Modus `fg-heading-(N+1)' colors."
  (when (fboundp 'modus-themes-get-color-value)
    (dotimes (n 4)
      (set-face-attribute
       (intern (format "ilist-plus-entry-face-%d" n)) nil
       :foreground (modus-themes-get-color-value
                    (intern (format "fg-heading-%d" (1+ n))) t)))))

;; Redefine the face when the theme changes.
(defun ilist-plus--theme-change-setup (&rest _)
  (set-face-attribute 'ilist-plus-modified-face nil
		      :background (ilist-plus--modus-color 'bg-changed nil "yellow"))
  (ilist-plus--modus-apply-heading-colors))


(defun ilist-plus--section-modified-p (start end buffer)
  "Return non-nil if BUFFER has a `diff-hl' hunk overlapping (START, END)."
  (when (and start end)
    (with-current-buffer buffer
      (let ((ovs (overlays-in start end))
            found)
        (while (and ovs (not found))
          (setq found (overlay-get (car ovs) 'diff-hl-hunk))
          (setq ovs (cdr ovs)))
        found))))

(defun ilist-plus--entry-range (entry buffer)
  "ENTRY's true (BEG . END) span, or nil if it has no position of its
own or BUFFER's indexer doesn't tag ranges (see
`ilist-plus--range-table', elisp-only via
`ilist-plus-elisp-parse-and-tag-ranges'). Looks up ENTRY's own
`ilist-plus--entry-position' (normalized to a plain integer, since two
distinct marker objects at the same buffer position are not `eql') in
BUFFER's range table -- this works for the synthetic \"\" declaration leaf
`ilist-plus-elisp-build-header' fabricates for a Section/Subsection header
too, since that leaf's position is the same raw position the header's own
leaf in RAW was keyed under when the table was built."
  (let ((pos (ilist-plus--entry-position entry)))
    (when pos
      (let ((key (if (markerp pos) (marker-position pos) pos))
            (table (buffer-local-value 'ilist-plus--range-table buffer)))
        (and table (gethash key table))))))

(defun ilist-plus--mark-modified (entries buffer index-table leaf-modified)
  "Mark LEAF-MODIFIED (via INDEX-TABLE, a hash table from entry to its
index in the flattened, display-order list) for every leaf in ENTRIES --
any nesting depth -- whose own `ilist-plus--entry-range' overlaps a
`diff-hl' hunk in BUFFER, per `ilist-plus--section-modified-p'. A
container is marked whenever any of its descendants is (plain recursive
OR, no separate span check of its own). Ranges are computed once, up
front, from true physical adjacency across every entry regardless of
category (see `ilist-plus-elisp-parse-and-tag-ranges'), so they already
partition the buffer without any gaps. Returns non-nil if anything in
ENTRIES or their descendants got marked."
  (let (any-modified)
    (dolist (entry entries)
      (let ((modified
             (if (imenu--subalist-p entry)
                 (ilist-plus--mark-modified (cdr entry) buffer index-table leaf-modified)
	       (let ((range (ilist-plus--entry-range entry buffer)))
                 (and range (ilist-plus--section-modified-p (car range) (cdr range) buffer))))))
        (when modified
          (aset leaf-modified (gethash entry index-table) t)
          (setq any-modified t))))
    any-modified))

(defun ilist-plus-highlight-modified-entries (ibuf)
  "Overlay `ilist-plus-modified-face' on the lines of the Ilist buffer
IBUF covering a source section with a pending `diff-hl' change, via
`ilist-plus--mark-modified'."
  (let ((src-buf (buffer-local-value 'ilist-plus--source ibuf))
        (entries (buffer-local-value 'ilist-plus--entries ibuf)))
    (when (buffer-live-p src-buf)
      (let* ((nodes (ilist-plus--build-nodes entries))
             (n (length nodes))
             (leaf-modified (make-vector n nil))
             (index-table (make-hash-table :test 'eq))
             (i 0))
        (dolist (node nodes)
          (puthash (ilist-plus--node-entry node) i index-table)
          (setq i (1+ i)))
        (ilist-plus--mark-modified entries src-buf index-table leaf-modified)
        (with-current-buffer ibuf
          (remove-overlays (point-min) (point-max) 'ilist-plus-modified t)
          (let ((inhibit-read-only t))
            (dotimes (i n)
	      (when (aref leaf-modified i)
                (save-excursion
                  (goto-char (point-min))
                  (forward-line i)
                  (let ((ov (make-overlay (line-beginning-position) (line-end-position))))
                    (overlay-put ov 'ilist-plus-modified t)
                    (overlay-put ov 'face 'ilist-plus-modified-face)))))))))))


;;; Global minor mode

;; Everything the mode installs -- hooks on `emacs-lisp-mode-hook'/`enable-theme-functions', the
;; mode-line format and the `imenu-list-smart-toggle' redirection -- is inherently global, so this
;; is a `:global' minor mode rather than a buffer-local one.  The Ilist itself (`ilist-plus-toggle')
;; works without it.

(defvar ilist-plus-mode--saved-mode-line-format nil
  "`imenu-list-mode-line-format' as it was before `ilist-plus-mode' set its own.")

(defun ilist-plus-mode--enable ()
  (ilist-plus--modus-apply-heading-colors)
  (when (and ilist-plus-imenu-list-compat (boundp 'imenu-list-mode-line-format))
    (setq ilist-plus-mode--saved-mode-line-format imenu-list-mode-line-format)
    (setq imenu-list-mode-line-format (ilist-plus--build-mode-line-format)))
  (add-hook 'emacs-lisp-mode-hook #'ilist-plus--elisp-mode-setup)
  ;; The hook only fires for buffers created from now on; the mode is often enabled lazily, so
  ;; give already-open elisp buffers the Sections/Use-package entries the hierarchy needs.
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (derived-mode-p 'emacs-lisp-mode)
        (ilist-plus--elisp-mode-setup))))
  (add-hook 'enable-theme-functions #'ilist-plus--theme-change-setup)
  (add-hook 'delete-frame-functions #'ilist-plus--frame-deleted)
  ;; Keeps existing `imenu-list-smart-toggle' key bindings working if in compat mode
  (when ilist-plus-imenu-list-compat
    (advice-add 'imenu-list-smart-toggle :override #'ilist-plus-toggle)))

(defun ilist-plus-mode--disable ()
  (when (and ilist-plus-imenu-list-compat (boundp 'imenu-list-mode-line-format))
    (setq imenu-list-mode-line-format ilist-plus-mode--saved-mode-line-format))
  (remove-hook 'emacs-lisp-mode-hook #'ilist-plus--elisp-mode-setup)
  (remove-hook 'enable-theme-functions #'ilist-plus--theme-change-setup)
  (remove-hook 'delete-frame-functions #'ilist-plus--frame-deleted)
  (when ilist-plus-imenu-list-compat
    (advice-remove 'imenu-list-smart-toggle #'ilist-plus-toggle)))

;;;###autoload
(define-minor-mode ilist-plus-mode
  "Toggle ilist-plus's UI and elisp/org indexing extensions."
  :global t
  :group 'ilist-plus
  (if ilist-plus-mode
      (ilist-plus-mode--enable)
    (ilist-plus-mode--disable)))

(provide 'ilist-plus)
;;; ilist-plus.el ends here
