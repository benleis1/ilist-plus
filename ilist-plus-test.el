;;; ilist-plus-test.el --- ERT tests for ilist-plus -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with (diff-hl must already be installed):
;;   emacs -Q --batch --eval "(progn (require 'package) (package-initialize))" \
;;     -l ilist-plus-test.el -f ert-run-tests-batch-and-exit
;;
;; Plain batch Emacs cannot create a second frame, so the multi-frame test is skipped there.
;; To run it for real, give Emacs a terminal, e.g.:
;;   script -q /dev/null emacs -nw -Q --eval "(progn (require 'package) (package-initialize))" \
;;     -l ilist-plus-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'diff-hl)
(require 'org)
(require 'treesit nil t)

(let ((dir (file-name-directory (or load-file-name buffer-file-name default-directory))))
  (add-to-list 'load-path dir))
(require 'ilist-plus)

;;; Test helpers

(defun ilist-plus-test--strip-positions (tree)
  "Replace every leaf position in TREE with `t', keeping names/structure."
  (mapcar (lambda (entry)
            (if (imenu--subalist-p entry)
                (cons (car entry) (ilist-plus-test--strip-positions (cdr entry)))
              (cons (car entry) t)))
          tree))

(defun ilist-plus-test--line-of (tree name)
  "0-based display line of the entry named NAME in flattened TREE."
  (cl-position name (ilist-plus--build-nodes tree)
               :key (lambda (node) (car (ilist-plus--node-entry node)))
               :test #'equal))

(defun ilist-plus-test--goto-line (n)
  (goto-char (point-min))
  (forward-line n))

(defconst ilist-plus-test--ibuf "*IListPlus-test*"
  "Name of the Ilist buffer the tests drive.")

(defun ilist-plus-test--reset-ilist-buffer (text &optional entries source)
  "Reset the test Ilist buffer to TEXT, showing ENTRIES of SOURCE, with no
leftover overlays."
  (with-current-buffer (get-buffer-create ilist-plus-test--ibuf)
    (unless (derived-mode-p 'ilist-plus-major-mode)
      (ilist-plus-major-mode))
    (let ((inhibit-read-only t))
      (erase-buffer)
      (remove-overlays (point-min) (point-max))
      (insert text))
    (setq ilist-plus--entries entries
          ilist-plus--source source
          ilist-plus--line-entries nil)
    (current-buffer)))

(defconst ilist-plus-test--decl (string #xf444)
  "Matches the icon glyph `ilist-plus-elisp-build-header' uses as the
name of the synthetic declaration leaf it fabricates for every header
-- not the empty string, despite how it may look when printed.")

(defconst ilist-plus-test--tree-simple
  '(("A" . 10) ("B" ("B1" . 20) ("B2" . 30)) ("C" . 40)))

(defconst ilist-plus-test--tree-nested
  '(("Root" ("Child1" ("GC1" . 100) ("GC2" . 110)) ("Child2" . 120))))

;;; General UI changes

(ert-deftest ilist-plus-test-modus-color-fallback ()
  (should (equal (ilist-plus--modus-color 'fg-test nil) "black"))
  (should (equal (ilist-plus--modus-color 'fg-test nil "red") "red")))

(ert-deftest ilist-plus-test-build-mode-line-format ()
  (let ((default (ilist-plus--build-mode-line-format))
        (custom-map (make-sparse-keymap)))
    (should (equal (car default) "%e"))
    (should (eq (plist-get (cddr (cadr default)) 'local-map)
                ilist-plus-default-key-map))
    (let ((custom (ilist-plus--build-mode-line-format custom-map)))
      (should (eq (plist-get (cddr (cadr custom)) 'local-map) custom-map)))))

;;; Direct, hideshow-free folding

(ert-deftest ilist-plus-test-build-nodes ()
  (let ((nodes (ilist-plus--build-nodes ilist-plus-test--tree-simple)))
    (should (equal (mapcar (lambda (node) (car (ilist-plus--node-entry node))) nodes)
                   '("A" "B" "B1" "B2" "C")))
    (should (equal (mapcar #'ilist-plus--node-depth nodes) '(0 0 1 1 0)))
    (should (equal (mapcar #'ilist-plus--node-level nodes) '(1 1 2 2 1)))
    (should (equal (mapcar #'ilist-plus--node-path nodes)
                   '(("A") ("B") ("B" "B1") ("B" "B2") ("C"))))
    (should (equal (mapcar #'ilist-plus--node-container-p nodes)
                   '(nil t nil nil nil)))
    (should (equal (mapcar #'ilist-plus--node-last-child nodes)
                   '(nil nil nil t t)))))

(ert-deftest ilist-plus-test-build-nodes-ancestor-last-children ()
  (let ((nodes (ilist-plus--build-nodes
                '(("Root" ("Child1" ("GC1" . 1) ("GC2" . 2)) ("Child2" . 3))))))
    (should (equal (mapcar #'ilist-plus--node-last-child nodes)
                   '(t nil nil t t)))
    ;; A top-level entry is never drawn as a parent, so its own last-child
    ;; stays out of its descendants' lists.
    (should (equal (mapcar #'ilist-plus--node-ancestor-last-children nodes)
                   '(nil nil (nil) (nil) nil)))))

(ert-deftest ilist-plus-test-subtree-end ()
  (let ((nodes (ilist-plus--build-nodes ilist-plus-test--tree-simple)))
    (should (= (ilist-plus--subtree-end nodes (length nodes) 1) 4))
    (should (= (ilist-plus--subtree-end nodes (length nodes) 4) 5))))

(ert-deftest ilist-plus-test-hide-show-folded-p ()
  (with-temp-buffer
    (insert "aaaaaaaaaa")
    (should-not (ilist-plus--folded-p 3))
    (ilist-plus--hide-region 2 5)
    (should (ilist-plus--folded-p 3))
    (should-not (ilist-plus--folded-p 6))
    (ilist-plus--show-region 2 5)
    (should-not (ilist-plus--folded-p 3))))

(ert-deftest ilist-plus-test-fold-below-depth ()
  (progn
    (ilist-plus-test--reset-ilist-buffer "A\n▼ B\n  B1\n  B2\nC\n" ilist-plus-test--tree-simple)
    (ilist-plus-fold-below-depth 1 ilist-plus-test--ibuf)
    (with-current-buffer ilist-plus-test--ibuf
      (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-simple "B1"))
      (should (ilist-plus--folded-p (point)))
      (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-simple "B2"))
      (should (ilist-plus--folded-p (point)))
      (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-simple "B"))
      (should-not (ilist-plus--folded-p (point)))
      (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-simple "C"))
      (should-not (ilist-plus--folded-p (point))))))

(ert-deftest ilist-plus-test-toggle-at-point ()
  (progn
    (ilist-plus-test--reset-ilist-buffer "A\n▼ B\n  B1\n  B2\nC\n" ilist-plus-test--tree-simple)
    (with-current-buffer ilist-plus-test--ibuf
      (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-simple "B"))
      (ilist-plus-toggle-at-point)
      (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-simple "B1"))
      (should (ilist-plus--folded-p (point)))
      (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-simple "B"))
      (ilist-plus-toggle-at-point)
      (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-simple "B1"))
      (should-not (ilist-plus--folded-p (point))))))

(ert-deftest ilist-plus-test-fold-children ()
  (progn
    (ilist-plus-test--reset-ilist-buffer "Root\n  Child1\n    GC1\n    GC2\n  Child2\n" ilist-plus-test--tree-nested)
    (with-current-buffer ilist-plus-test--ibuf
      (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-nested "Root"))
      (ilist-plus-fold-children))
    (with-current-buffer ilist-plus-test--ibuf
      (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-nested "GC1"))
      (should (ilist-plus--folded-p (point)))
      (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-nested "GC2"))
      (should (ilist-plus--folded-p (point)))
      (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-nested "Child1"))
      (should-not (ilist-plus--folded-p (point)))
      (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-nested "Child2"))
      (should-not (ilist-plus--folded-p (point))))))

(ert-deftest ilist-plus-test-record-and-restore-folded-paths ()
  (let ((src (generate-new-buffer "ilist-plus-test-src")))
    (unwind-protect
        (progn
          (ilist-plus-test--reset-ilist-buffer "Root\n  Child1\n    GC1\n    GC2\n  Child2\n"
                                               ilist-plus-test--tree-nested src)
          (with-current-buffer ilist-plus-test--ibuf
            (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-nested "Child1"))
            (ilist-plus-toggle-at-point))
          (ilist-plus--record-folded-paths (get-buffer ilist-plus-test--ibuf))
          (should (equal (buffer-local-value 'ilist-plus--folded-paths src)
                         '(("Root" "Child1"))))
          (ilist-plus-test--reset-ilist-buffer "Root\n  Child1\n    GC1\n    GC2\n  Child2\n"
                                               ilist-plus-test--tree-nested src)
          (with-current-buffer ilist-plus-test--ibuf
            (ilist-plus--restore-folded-paths (buffer-local-value 'ilist-plus--folded-paths src))
            (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-nested "GC1"))
            (should (ilist-plus--folded-p (point)))
            (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-nested "Child1"))
            (should-not (ilist-plus--folded-p (point)))))
      (kill-buffer src))))

(ert-deftest ilist-plus-test-restore-folded-paths-does-not-pile-up-overlays ()
  (let ((src (generate-new-buffer "ilist-plus-test-src-overlays")))
    (unwind-protect
        (progn
          (ilist-plus-test--reset-ilist-buffer "Root\n  Child1\n    GC1\n    GC2\n  Child2\n"
                                               ilist-plus-test--tree-nested src)
          (with-current-buffer ilist-plus-test--ibuf
            (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-nested "Child1"))
            (ilist-plus-toggle-at-point))
          (let ((paths (buffer-local-value 'ilist-plus--folded-paths src)))
            (with-current-buffer ilist-plus-test--ibuf
              (dotimes (_ 5)
                (ilist-plus--restore-folded-paths paths))
              (should (= 1 (length (seq-filter
                                    (lambda (ov) (overlay-get ov 'ilist-plus-fold))
                                    (overlays-in (point-min) (point-max)))))))))
      (kill-buffer src))))

(ert-deftest ilist-plus-test-fold-below-depth-once-dispatches-on-folded-flag ()
  (let ((src (generate-new-buffer "ilist-plus-test-src2")))
    (unwind-protect
        (progn
          (with-current-buffer src
            (setq-local ilist-plus--folded-once nil)
            (setq-local ilist-plus--folded-paths nil))
          (ilist-plus-test--reset-ilist-buffer "Root\n  Child1\n    GC1\n    GC2\n  Child2\n"
                                               ilist-plus-test--tree-nested src)
          (ilist-plus-fold-below-depth-once (get-buffer ilist-plus-test--ibuf) 2)
          (should (buffer-local-value 'ilist-plus--folded-once src))
          (with-current-buffer ilist-plus-test--ibuf
            (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-nested "GC1"))
            (should (ilist-plus--folded-p (point))))
          ;; Simulate a differing, previously-saved snapshot: the once-flag
          ;; being set must make the second call restore it verbatim rather
          ;; than recompute a fresh depth-based fold.
          (with-current-buffer src
            (setq-local ilist-plus--folded-paths '(("Root"))))
          (ilist-plus-test--reset-ilist-buffer "Root\n  Child1\n    GC1\n    GC2\n  Child2\n"
                                               ilist-plus-test--tree-nested src)
          (ilist-plus-fold-below-depth-once (get-buffer ilist-plus-test--ibuf) 2)
          (with-current-buffer ilist-plus-test--ibuf
            (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-nested "Child1"))
            (should (ilist-plus--folded-p (point)))
            (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-nested "GC1"))
            (should (ilist-plus--folded-p (point)))))
      (kill-buffer src))))

(ert-deftest ilist-plus-test-update-fold-markers ()
  (progn
    (ilist-plus-test--reset-ilist-buffer "A\n▼ B\n  B1\n  B2\nC\n" ilist-plus-test--tree-simple)
    (with-current-buffer ilist-plus-test--ibuf
      (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-simple "B"))
      (ilist-plus-toggle-at-point)
      (ilist-plus-test--goto-line 1)
      (should (equal (get-text-property (point) 'display) ilist-plus-collapsed-marker))
      (ilist-plus-toggle-at-point)
      (ilist-plus-test--goto-line 1)
      (should-not (get-text-property (point) 'display)))))

;;; Tree styles

(defun ilist-plus-test--render (style)
  "Render `ilist-plus-test--tree-nested' in STYLE; return the test Ilist buffer."
  (ilist-plus-test--reset-ilist-buffer "" ilist-plus-test--tree-nested
                                       ilist-plus-test--tree-nested)
  (with-current-buffer ilist-plus-test--ibuf
    (let ((ilist-plus-tree-style style))
      (ilist-plus--insert-entries)
      (ilist-plus-update-fold-markers))
    (current-buffer)))

(defun ilist-plus-test--lines (ibuf)
  (split-string (with-current-buffer ibuf (buffer-substring-no-properties (point-min) (point-max)))
                "\n" t))

(defun ilist-plus-test--fold-line (ibuf name)
  "Toggle the fold of the container NAME in IBUF under the current style."
  (with-current-buffer ibuf
    (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-nested name))
    (ilist-plus-toggle-at-point)))

(ert-deftest ilist-plus-test-tree-style-classic-render ()
  (should (equal (ilist-plus-test--lines (ilist-plus-test--render 'classic))
                 '("▼ Root" "   ▼ Child1" "     GC1" "     GC2" "   Child2"))))

(ert-deftest ilist-plus-test-tree-style-straight-render ()
  (should (equal (ilist-plus-test--lines (ilist-plus-test--render 'straight))
                 '("Root" "├─ Child1" "│  ├─ GC1" "│  └─ GC2" "└─ Child2"))))

(ert-deftest ilist-plus-test-tree-style-curved-render ()
  (should (equal (ilist-plus-test--lines (ilist-plus-test--render 'curved))
                 '("Root" "├─ Child1" "│  ├─ GC1" "│  ╰─ GC2" "╰─ Child2"))))

(ert-deftest ilist-plus-test-tree-style-expanded-has-no-overlay ()
  (dolist (style '(classic straight curved))
    (with-current-buffer (ilist-plus-test--render style)
      (should-not (text-property-not-all (point-min) (point-max) 'display nil)))))

(ert-deftest ilist-plus-test-tree-style-collapsed-marker ()
  (dolist (style '(classic straight curved))
    (let ((ibuf (ilist-plus-test--render style))
          (ilist-plus-tree-style style))
      (ilist-plus-test--fold-line ibuf "Child1")
      (with-current-buffer ibuf
        (ilist-plus-test--goto-line 1)
        (let* ((pos (text-property-not-all (point) (line-end-position) 'display nil))
               (display (and pos (get-text-property pos 'display))))
          (should pos)
          (should (string-prefix-p ilist-plus-collapsed-marker display))
          (should (= (length display)
                     (if (eq style 'classic) 1 3))))
        (ilist-plus-toggle-at-point)
        (ilist-plus-test--goto-line 1)
        (should-not (text-property-not-all (point) (line-end-position) 'display nil))))))

(ert-deftest ilist-plus-test-tree-style-setter-redraws-open-buffers ()
  (let* ((frame (selected-frame))
         (ibuf (ilist-plus--get-buffer frame))
         (src (generate-new-buffer "ilist-plus-test-style-src"))
         (orig ilist-plus-tree-style)
         (text (lambda () (with-current-buffer ibuf
                            (buffer-substring-no-properties (point-min) (point-max))))))
    (unwind-protect
        (progn
          (with-current-buffer src
            (insert "x")
            (setq-local imenu-create-index-function
                        (lambda () (copy-tree ilist-plus-test--tree-nested))))
          (customize-set-variable 'ilist-plus-tree-style 'classic)
          (ilist-plus-update t frame src)
          (should (string-match-p "▼ Root" (funcall text)))
          (customize-set-variable 'ilist-plus-tree-style 'straight)
          (should (string-match-p "└─ GC2" (funcall text)))
          (customize-set-variable 'ilist-plus-tree-style 'curved)
          (should (string-match-p "╰─ GC2" (funcall text))))
      (customize-set-variable 'ilist-plus-tree-style orig)
      (kill-buffer src)
      (kill-buffer ibuf))))

(ert-deftest ilist-plus-test-rebind-buttons ()
  (ilist-plus-test--reset-ilist-buffer "hello\n")
  (with-current-buffer ilist-plus-test--ibuf
    (let ((ov (make-button (point-min) (point-max))))
      (should (eq (overlay-get ov 'keymap) button-map))
      (ilist-plus--rebind-buttons)
      (should (eq (overlay-get ov 'keymap) ilist-plus-button-keymap))
      (ilist-plus--rebind-buttons)
      (should (eq (overlay-get ov 'keymap) ilist-plus-button-keymap)))))

(ert-deftest ilist-plus-test-reset-fold-state ()
  (let ((b1 (generate-new-buffer "ilist-plus-test-b1"))
        (b2 (generate-new-buffer "ilist-plus-test-b2")))
    (unwind-protect
        (progn
          (dolist (b (list b1 b2))
            (with-current-buffer b
              (setq-local ilist-plus--folded-once t)
              (setq-local ilist-plus--folded-paths '(("x")))))
          (ilist-plus-reset-fold-state (list b2))
          (should-not (buffer-local-value 'ilist-plus--folded-once b1))
          (should-not (buffer-local-value 'ilist-plus--folded-paths b1))
          (should (buffer-local-value 'ilist-plus--folded-once b2))
          (should (buffer-local-value 'ilist-plus--folded-paths b2))
          (ilist-plus-reset-fold-state)
          (should-not (buffer-local-value 'ilist-plus--folded-once b2)))
      (kill-buffer b1)
      (kill-buffer b2))))

;;; Sorting

(ert-deftest ilist-plus-test-compare ()
  (should (ilist-plus-compare '("a" . 1) '("b" . 2)))
  (should-not (ilist-plus-compare '("b" . 1) '("a" . 2))))

(ert-deftest ilist-plus-test-current-sort ()
  (with-temp-buffer
    (setq-local ilist-plus-sort-strategy 'alphabetical)
    (should (equal (ilist-plus-current-sort) "alpha"))
    (should (equal (ilist-plus-current-sort (current-buffer)) "alpha")))
  (with-temp-buffer
    (setq-local ilist-plus-sort-strategy 'by-type)
    (should (equal (ilist-plus-current-sort) "by-type")))
  (with-temp-buffer
    (should (equal (ilist-plus-current-sort) "pos"))))

(ert-deftest ilist-plus-test-sort-alphabetically ()
  (with-temp-buffer
    (setq imenu--index-alist '(("Cat2" ("bb" . 1) ("aa" . 2))
                                ("z-leaf" . 100)
                                ("Cat1" ("dd" . 3) ("cc" . 4))
                                ("a-leaf" . 200)))
    (should (equal (ilist-plus-sort-alphabetically)
                   '(("Cat2" ("aa" . 2) ("bb" . 1))
                     ("Cat1" ("cc" . 4) ("dd" . 3))
                     ("a-leaf" . 200)
                     ("z-leaf" . 100))))))

;;; Elisp custom header handling: small pure helpers

(ert-deftest ilist-plus-test-elisp-flatten-raw ()
  (let* ((raw '(("plain1" . 10)
                ("Cat" ("leaf1" . 20) ("leaf2" . 30))
                ("plain2" . 40)))
         (leaves (ilist-plus-elisp-flatten-raw raw)))
    (should (equal (sort (mapcar #'car leaves) #'string<)
                   '("leaf1" "leaf2" "plain1" "plain2")))))

(ert-deftest ilist-plus-test-elisp-ranges ()
  (with-temp-buffer
    (insert (make-string 99 ?x))
    (let ((ranges (ilist-plus-elisp-ranges '(("a" . 10) ("b" . 20) ("c" . 30)))))
      (should (equal (nth 0 ranges) '("a" 10 20)))
      (should (equal (nth 1 ranges) '("b" 20 30)))
      (should (equal (nth 2 ranges) (list "c" 30 (point-max)))))))

(ert-deftest ilist-plus-test-elisp-find-section ()
  (let ((ranges '(("Sec1" 1 50) ("Sec2" 50 100))))
    (should (equal (ilist-plus-elisp-find-section ranges 30) "Sec1"))
    (should (equal (ilist-plus-elisp-find-section ranges 70) "Sec2"))
    (should-not (ilist-plus-elisp-find-section ranges 150))
    (should-not (ilist-plus-elisp-find-section ranges 0))))

(ert-deftest ilist-plus-test-elisp-bucket-by-section ()
  (let* ((entries '(("a" . 5) ("b" . 60) ("c" . 120)))
         (ranges '(("Sec1" 10 100) ("Sec2" 100 200)))
         (bucketed (ilist-plus-elisp-bucket-by-section entries ranges))
         (buckets (car bucketed))
         (orphans (cdr bucketed)))
    (should (equal (gethash "Sec1" buckets) '(("b" . 60))))
    (should (equal (gethash "Sec2" buckets) '(("c" . 120))))
    (should (equal orphans '(("a" . 5))))))

(ert-deftest ilist-plus-test-elisp-nest-under-code ()
  (let ((sections '(("Commentary" ("" . 1))
                     ("Code:" ("" . 100))
                     ("Section1" ("" . 200))
                     ("Section2" ("" . 300)))))
    (should (equal (ilist-plus-elisp-nest-under-code sections)
                   '(("Commentary" ("" . 1))
                     ("Code" ("" . 100) ("Section1" ("" . 200)) ("Section2" ("" . 300)))))))
  (let ((sections '(("Commentary" ("" . 1)) ("Section1" ("" . 200)))))
    (should (equal (ilist-plus-elisp-nest-under-code sections) sections))))

(ert-deftest ilist-plus-test-elisp-build-header ()
  (let ((fn-buckets (make-hash-table :test 'equal))
        (pkg-buckets (make-hash-table :test 'equal))
        (var-buckets (make-hash-table :test 'equal)))
    (puthash "Sec1" '(("f1" . 10)) fn-buckets)
    (puthash "Sec1" '(("pkg1" . 20)) pkg-buckets)
    (puthash "Sec1" '(("v1" . 30)) var-buckets)
    (should (equal (ilist-plus-elisp-build-header
                    "Sec1" 5 fn-buckets pkg-buckets `(("Variables" . ,var-buckets))
                    '(("Sub1" ("" . 40))))
                   `("Sec1" (,ilist-plus-test--decl . 5)
                     ("Use-package" ("pkg1" . 20))
                     ("Variables" ("v1" . 30))
                     ("f1" . 10)
                     ("Sub1" ("" . 40)))))))

(ert-deftest ilist-plus-test-elisp-back-over-comments ()
  (with-temp-buffer
    (insert ";; leading comment 1\n;; leading comment 2\n(defun myfun () nil)\n")
    (goto-char (point-min))
    (search-forward "myfun")
    ;; FLOOR here is `point-min' itself (no earlier entry) -- since the
    ;; walk requires strictly crossing above FLOOR's own line, the very
    ;; first comment line (which starts exactly at FLOOR) is never
    ;; swallowed, so only the second comment line backs over.
    (should (= (ilist-plus-elisp-back-over-comments (point) (current-buffer) (point-min))
               (save-excursion (goto-char (point-min)) (forward-line 1) (point)))))
  (with-temp-buffer
    (insert "(defun other () nil)\n;; comment for myfun\n(defun myfun () nil)\n")
    (goto-char (point-min))
    (search-forward "other")
    (let ((floor (point)))
      (goto-char (point-min))
      (search-forward "myfun")
      (should (= (ilist-plus-elisp-back-over-comments (point) (current-buffer) floor)
                 (save-excursion (goto-char (point-min)) (forward-line 1) (point)))))))

;;; Elisp indexer integration

(ert-deftest ilist-plus-test-elisp-parse-and-tag-ranges ()
  (with-temp-buffer
    (emacs-lisp-mode)
    (insert ";; comment for a\n(defvar a 1)\n(defvar b 2)\n")
    (let* ((raw (ilist-plus-elisp-parse-and-tag-ranges))
           (leaves (ilist-plus-elisp-flatten-raw raw))
           (a (assoc "a" leaves))
           (b (assoc "b" leaves))
           (a-range (gethash (marker-position (cdr a)) ilist-plus--range-table))
           (b-range (gethash (marker-position (cdr b)) ilist-plus--range-table)))
      ;; FLOOR for the very first entry is `point-min' itself, so the
      ;; leading comment (which starts exactly at FLOOR) isn't backed
      ;; over -- see `ilist-plus-test-elisp-back-over-comments'.
      (should (= (car a-range) (save-excursion (goto-char (point-min)) (forward-line 1) (point))))
      (should (= (cdr a-range) (car b-range)))
      (should (= (cdr b-range) (point-max)))
      (should (= (car b-range) (save-excursion (goto-char (point-min)) (forward-line 2) (point)))))))

(ert-deftest ilist-plus-test-elisp-index-by-position ()
  (with-temp-buffer
    (emacs-lisp-mode)
    (ilist-plus--elisp-mode-setup)
    (insert ";;; Header stuff\n\n;;; Code:\n\n(defvar ilist-plus-test-var nil \"doc\")\n\n;;; Section A\n\n;;;; Sub A1\n(defun test-fn-a1 () nil)\n\n;;;; Sub A2\n(defun test-fn-a2 () nil)\n\n;;; Section B\n(use-package foo-pkg)\n(defun test-fn-b1 () nil)\n(defcustom my-custom-thing 1 \"doc\")\n")
    ;; `ilist-plus-elisp-nest-under-code' folds every section following
    ;; ";;; Code:" underneath it, so Section A/B end up nested inside
    ;; "Code" rather than as its top-level siblings.
    (should (equal (ilist-plus-test--strip-positions (ilist-plus-elisp-index-by-position))
                   `(("Header stuff" (,ilist-plus-test--decl . t))
                     ("Code" (,ilist-plus-test--decl . t)
                      ("Variables" ("ilist-plus-test-var" . t))
                      ("Section A" (,ilist-plus-test--decl . t)
                       ("Sub A1" (,ilist-plus-test--decl . t) ("test-fn-a1" . t))
                       ("Sub A2" (,ilist-plus-test--decl . t) ("test-fn-a2" . t)))
                      ("Section B" (,ilist-plus-test--decl . t)
                       ("Use-package" ("foo-pkg" . t))
                       ("Variables" ("my-custom-thing" . t))
                       ("test-fn-b1" . t))))))))

(ert-deftest ilist-plus-test-elisp-index-by-type ()
  (with-temp-buffer
    (emacs-lisp-mode)
    (ilist-plus--elisp-mode-setup)
    (setq-local ilist-plus-sort-strategy 'by-type)
    (insert ";;; Header stuff\n\n;;; Code:\n\n(defvar ilist-plus-test-var nil \"doc\")\n\n;;; Section A\n\n;;;; Sub A1\n(defun test-fn-a1 () nil)\n\n;;;; Sub A2\n(defun test-fn-a2 () nil)\n\n;;; Section B\n(use-package foo-pkg)\n(defun test-fn-b1 () nil)\n(defcustom my-custom-thing 1 \"doc\")\n")
    (should (equal (ilist-plus-test--strip-positions (ilist-plus-elisp-index))
                   '(("Functions" ("test-fn-a1" . t) ("test-fn-a2" . t) ("test-fn-b1" . t))
                     ("Variables" ("ilist-plus-test-var" . t) ("my-custom-thing" . t))
                     ("Use-package" ("foo-pkg" . t)))))))

;;; Hierarchical treesitter tree parsing (java)

(ert-deftest ilist-plus-test-java-ts-index ()
  (skip-unless (and (fboundp 'treesit-language-available-p)
                    (treesit-language-available-p 'java)))
  (with-temp-buffer
    (insert "class Foo {\n"
            "    private int x;\n\n"
            "    public Foo() {\n    }\n\n"
            "    public void bar() {\n    }\n\n"
            "    public void baz() {\n    }\n\n"
            "    class Inner {\n        void innerMethod() {}\n    }\n"
            "}\n\n"
            "interface Baz {\n    void doIt();\n}\n\n"
            "enum Color {\n    RED, GREEN, BLUE\n}\n")
    (java-ts-mode)
    (should (equal (ilist-plus-test--strip-positions (ilist-plus-java-ts-index (current-buffer)))
                   '(("Interfaces" ("Baz" ("declaration" . t) ("Methods" ("doIt" . t))))
                     ("Classes" ("Foo" ("declaration" . t)
                                 ("Constructors" ("Foo" . t))
                                 ("Fields" ("x" . t))
                                 ("Methods" ("bar" . t) ("baz" . t))
                                 ("Inner Classes" ("Inner" ("declaration" . t) ("Methods" ("innerMethod" . t))))))
                     ("Enums" ("Color" ("declaration" . t))))))))

;;; Current-entry tracking (including org container headings)

(ert-deftest ilist-plus-test-entry-position-and-current-entry ()
  (let ((line-entries (list (cons "e1" 10) (cons "e2" 20) (cons "e3" 30))))
    (with-temp-buffer
      (insert (make-string 50 ?x))
      (goto-char 25)
      (should (equal (ilist-plus--current-entry line-entries) (cons "e2" 20)))))
  (let* ((marker (with-temp-buffer (insert "* Heading\n") (point-min-marker)))
         (name (propertize "Heading" 'org-imenu-marker marker))
         (container-entry (cons name (list (cons "child" 5)))))
    (should (equal (ilist-plus--entry-position container-entry) marker))))

;;; VC Highlighting

(ert-deftest ilist-plus-test-section-modified-p ()
  (let ((buf (generate-new-buffer "ilist-plus-test-modified")))
    (unwind-protect
        (with-current-buffer buf
          (insert (make-string 100 ?x))
          (let ((ov (make-overlay 10 20)))
            (overlay-put ov 'diff-hl-hunk t)
            (should (ilist-plus--section-modified-p 5 15 buf))
            (should-not (ilist-plus--section-modified-p 50 60 buf))
            (should-not (ilist-plus--section-modified-p nil 15 buf))))
      (kill-buffer buf))))

(ert-deftest ilist-plus-test-highlight-modified-entries ()
  (let ((src (generate-new-buffer "ilist-plus-test-elisp-src")))
    (unwind-protect
        (progn
          (with-current-buffer src
            (emacs-lisp-mode)
            (ilist-plus--elisp-mode-setup)
            (insert ";;; Header\n\n;;; Code:\n\n;;; Section A\n\n;;;; Sub A1\n(defun test-fn-a1 () nil)\n\n;;;; Sub A2\n(defun test-fn-a2 () nil)\n"))
          (let* ((entries (with-current-buffer src (ilist-plus-elisp-index-by-position)))
                 (flat (ilist-plus--build-nodes entries)))
            (with-current-buffer src
              (goto-char (point-min))
              (search-forward "test-fn-a1")
              (overlay-put (make-overlay (point) (+ (point) 5)) 'diff-hl-hunk t))
            (ilist-plus-test--reset-ilist-buffer
             (concat (mapconcat (lambda (_) "x") flat "\n") "\n") entries src)
            (ilist-plus-highlight-modified-entries (get-buffer ilist-plus-test--ibuf))
            (cl-labels ((marked-p (name)
                          (with-current-buffer ilist-plus-test--ibuf
                            (save-excursion
                              (ilist-plus-test--goto-line (ilist-plus-test--line-of entries name))
                              (cl-some (lambda (ov) (overlay-get ov 'ilist-plus-modified))
                                       (overlays-in (line-beginning-position) (line-end-position)))))))
              (should (marked-p "test-fn-a1"))
              (should (marked-p "Sub A1"))
              (should (marked-p "Section A"))
              (should (marked-p "Code"))
              (should-not (marked-p "test-fn-a2"))
              (should-not (marked-p "Sub A2"))
              (should-not (marked-p "Header")))))
      (kill-buffer src))))

;;; Org mode optimization

(ert-deftest ilist-plus-test-collect-entries-skips-unmodified-org-rescan ()
  (let ((ibuf (ilist-plus-test--reset-ilist-buffer "")))
    (with-temp-buffer
      (org-mode)
      (insert "* Heading\n")
      (let ((rescans 0))
        (cl-letf (((symbol-function 'ilist-plus--rescan-imenu)
                   (lambda ()
                     (setq rescans (1+ rescans))
                     (setq imenu--index-alist '(("stub" . 1))))))
          (ilist-plus--collect-entries ibuf)
          (should (= rescans 1))
          (should (equal ilist-plus--last-tick (buffer-chars-modified-tick)))
          (ilist-plus--collect-entries ibuf)
          (should (= rescans 1))
          (should (eq (buffer-local-value 'ilist-plus--entries ibuf) imenu--index-alist))
          (should (eq (buffer-local-value 'ilist-plus--source ibuf) (current-buffer)))
          (insert "more text")
          (ilist-plus--collect-entries ibuf)
          (should (= rescans 2)))))))

;;; Per-frame buffers

(ert-deftest ilist-plus-test-buffer-names-follow-frame-id ()
  (let ((frame (selected-frame)))
    (should (equal (ilist-plus--buffer-name frame)
                   (format "*IListPlus[%d]*" (ilist-plus--frame-id frame))))
    (should (= (ilist-plus--frame-id frame) (ilist-plus--frame-id frame)))))

(ert-deftest ilist-plus-test-get-buffer-is-per-frame-and-killed-with-it ()
  (let* ((frame (selected-frame))
         (ibuf (ilist-plus--get-buffer frame)))
    (unwind-protect
        (progn
          (should (eq ibuf (ilist-plus--buffer frame)))
          (should (ilist-plus--ilist-buffer-p ibuf))
          (should (eq (buffer-local-value 'ilist-plus--frame ibuf) frame))
          (should (memq ibuf (ilist-plus--buffers)))
          (ilist-plus--frame-deleted frame)
          (should-not (buffer-live-p ibuf)))
      (when (buffer-live-p ibuf) (kill-buffer ibuf)))))

(ert-deftest ilist-plus-test-update-fills-only-its-own-buffer ()
  (let* ((frame (selected-frame))
         (ibuf (ilist-plus--get-buffer frame))
         (other (ilist-plus-test--reset-ilist-buffer "untouched\n" '(("keep" . 1)))))
    (unwind-protect
        (let ((src (generate-new-buffer "ilist-plus-test-update-src")))
          (with-current-buffer src
            (emacs-lisp-mode)
            (insert "(defun first-fn () nil)\n(defun second-fn () nil)\n"))
          (ilist-plus-update t frame src)
          (should (eq (buffer-local-value 'ilist-plus--source ibuf) src))
          (should (cl-find "first-fn" (buffer-local-value 'ilist-plus--line-entries ibuf)
                           :key #'car :test #'equal))
          (should (string-match-p "second-fn" (with-current-buffer ibuf (buffer-string))))
          (should (equal (buffer-local-value 'ilist-plus--entries other) '(("keep" . 1))))
          (should (equal (with-current-buffer other (buffer-string)) "untouched\n"))
          (kill-buffer src))
      (kill-buffer ibuf))))

;;; imenu-list compatibility

(defvar imenu-list-size)
(defvar imenu-list-custom-position-translator)

(ert-deftest ilist-plus-test-opt-honors-imenu-list-only-under-compat ()
  (let ((ilist-plus-size 0.3)
        (imenu-list-size 0.5))
    (let ((ilist-plus-imenu-list-compat nil))
      (should (= (ilist-plus--opt 'size) 0.3)))
    (let ((ilist-plus-imenu-list-compat t))
      (should (= (ilist-plus--opt 'size) 0.5))))
  ;; compat never fails when the imenu-list variable doesn't exist
  (unless (boundp 'imenu-list-custom-position-translator)
    (let ((ilist-plus-imenu-list-compat t)
          (ilist-plus-custom-position-translator 'identity))
      (should (eq (ilist-plus--opt 'custom-position-translator) 'identity)))))

(ert-deftest ilist-plus-test-compat-flag-defaults-off-and-never-loads-imenu-list ()
  (should-not (default-value 'ilist-plus-imenu-list-compat))
  (should-not (featurep 'imenu-list)))

;;; Multiple frames

(defun ilist-plus-test--make-frame ()
  "A new, usably sized frame, or nil when this Emacs cannot create one."
  (condition-case nil
      (let ((frame (make-frame)))
        (when (< (frame-width frame) 60)
          (set-frame-size frame 80 24))
        (if (and (>= (frame-width frame) 60) (>= (frame-height frame) 10))
            frame
          (delete-frame frame)
          nil))
    (error nil)))

(defun ilist-plus-test--ibuf-text (frame)
  (with-current-buffer (ilist-plus--buffer frame) (buffer-string)))

(ert-deftest ilist-plus-test-drop-duplicate-frame-id ()
  (let ((params (list (cons 'orig 1) (cons 'clone 1) (cons 'other 2))))
    (cl-letf (((symbol-function 'frame-list) (lambda () '(orig clone other)))
              ((symbol-function 'frame-parameter)
               (lambda (f _p) (alist-get f params)))
              ((symbol-function 'set-frame-parameter)
               (lambda (f _p v) (setf (alist-get f params) v))))
      (ilist-plus--drop-duplicate-frame-id 'other)
      (should (= 2 (alist-get 'other params)))
      (ilist-plus--drop-duplicate-frame-id 'clone)
      (should-not (alist-get 'clone params))
      (should (= 1 (alist-get 'orig params))))))

(ert-deftest ilist-plus-test-mode-installs-clone-frame-guard ()
  (let ((ilist-plus-mode nil))
    (unwind-protect
        (progn
          (ilist-plus-mode 1)
          (should (memq #'ilist-plus--drop-duplicate-frame-id after-make-frame-functions))
          (ilist-plus-mode -1)
          (should-not (memq #'ilist-plus--drop-duplicate-frame-id after-make-frame-functions)))
      (ilist-plus-mode -1))))

(ert-deftest ilist-plus-test-two-frames-toggle-and-view-independently ()
  (let ((ilist-plus-focus-after-activation nil)
        (f1 (selected-frame))
        (f2 (ilist-plus-test--make-frame))
        (a (generate-new-buffer "ilist-plus-test-frame-a"))
        (b (generate-new-buffer "ilist-plus-test-frame-b")))
    (skip-unless f2)
    (unwind-protect
        (progn
          (with-current-buffer a
            (emacs-lisp-mode)
            (insert "(defun frame-a-one () 1)\n(defun frame-a-two () 2)\n"))
          (with-current-buffer b
            (emacs-lisp-mode)
            (insert "(defun frame-b-one () 1)\n(defun frame-b-two () 2)\n(defun frame-b-three () 3)\n"))
          (select-frame f1)
          (switch-to-buffer a)
          (ilist-plus-toggle)
          (select-frame f2)
          (switch-to-buffer b)
          (ilist-plus-toggle)
          (let ((i1 (ilist-plus--buffer f1))
                (i2 (ilist-plus--buffer f2)))
            ;; separate buffers, each shown only in its own frame
            (should (and i1 i2 (not (eq i1 i2))))
            (should-not (equal (buffer-name i1) (buffer-name i2)))
            (should (get-buffer-window i1 f1))
            (should-not (get-buffer-window i1 f2))
            (should (get-buffer-window i2 f2))
            (should-not (get-buffer-window i2 f1))
            ;; opening leaves the source window selected
            (should (eq (window-buffer (frame-selected-window f2)) b))
            (should (eq (window-buffer (frame-selected-window f1)) a))
            ;; separate views of different sources
            (should (eq (buffer-local-value 'ilist-plus--source i1) a))
            (should (eq (buffer-local-value 'ilist-plus--source i2) b))
            (should (string-match-p "frame-a-two" (ilist-plus-test--ibuf-text f1)))
            (should-not (string-match-p "frame-b" (ilist-plus-test--ibuf-text f1)))
            (should (string-match-p "frame-b-three" (ilist-plus-test--ibuf-text f2)))
            (should-not (string-match-p "frame-a" (ilist-plus-test--ibuf-text f2)))
            ;; updating one frame's view leaves the other's untouched
            (let ((before (ilist-plus-test--ibuf-text f1)))
              (with-current-buffer b (goto-char (point-max)))
              (set-window-point (get-buffer-window b f2) (with-current-buffer b (point)))
              (ilist-plus-update nil f2)
              (should (equal (ilist-plus-test--ibuf-text f1) before))
              (should (eq (buffer-local-value 'ilist-plus--source i1) a)))
            ;; toggling is per frame
            (select-frame f2)
            (ilist-plus-toggle)
            (should-not (get-buffer-window i2 f2))
            (should (get-buffer-window i1 f1))
            (ilist-plus-toggle)
            (should (get-buffer-window i2 f2))
            (select-frame f1)
            (ilist-plus-toggle)
            (should-not (get-buffer-window i1 f1))
            (should (get-buffer-window i2 f2))
            ;; a frame's buffer goes away with the frame
            (delete-frame f2)
            (should-not (buffer-live-p i2))
            (should (buffer-live-p i1))))
      (when (frame-live-p f2) (delete-frame f2))
      (select-frame f1)
      (dolist (ibuf (ilist-plus--buffers))
        (when (get-buffer-window ibuf t)
          (quit-windows-on ibuf nil t))
        (kill-buffer ibuf))
      (ilist-plus--stop-timer)
      (kill-buffer a)
      (kill-buffer b))))

(provide 'ilist-plus-test)
;;; ilist-plus-test.el ends here
