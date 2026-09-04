;;; ilist-plus-test.el --- ERT tests for ilist-plus -*- lexical-binding: t; -*-

;;; Commentary:

;; Run with (imenu-list and diff-hl must already be installed):
;;   emacs -Q --batch --eval "(progn (require 'package) (package-initialize))" \
;;     -l ilist-plus-test.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'imenu-list)
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
  (cl-position name (ilist-plus--flatten-entries tree 0)
               :key (lambda (pair) (car (car pair))) :test #'equal))

(defun ilist-plus-test--goto-line (n)
  (goto-char (point-min))
  (forward-line n))

(defun ilist-plus-test--reset-ilist-buffer (text)
  "Reset the shared *Ilist* buffer to TEXT, with no leftover overlays."
  (with-current-buffer (get-buffer-create imenu-list-buffer-name)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (remove-overlays (point-min) (point-max))
      (insert text))
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
                ilist-plus-default-window-map))
    (let ((custom (ilist-plus--build-mode-line-format custom-map)))
      (should (eq (plist-get (cddr (cadr custom)) 'local-map) custom-map)))))

;;; Direct, hideshow-free folding

(ert-deftest ilist-plus-test-flatten-entries ()
  (let ((flat (ilist-plus--flatten-entries ilist-plus-test--tree-simple 0)))
    (should (equal (mapcar (lambda (p) (cons (car (car p)) (cdr p))) flat)
                   '(("A" . 0) ("B" . 0) ("B1" . 1) ("B2" . 1) ("C" . 0))))))

(ert-deftest ilist-plus-test-flatten-paths ()
  (should (equal (ilist-plus--flatten-paths ilist-plus-test--tree-simple nil)
                 '(("A") ("B") ("B" "B1") ("B" "B2") ("C")))))

(ert-deftest ilist-plus-test-subtree-end ()
  (let ((flat (ilist-plus--flatten-entries ilist-plus-test--tree-simple 0)))
    (should (= (ilist-plus--subtree-end flat (length flat) 1 1) 4))))

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
  (let ((imenu-list--imenu-entries ilist-plus-test--tree-simple))
    (ilist-plus-test--reset-ilist-buffer "A\n+ B\n  B1\n  B2\nC\n")
    (ilist-plus-fold-below-depth 1)
    (with-current-buffer imenu-list-buffer-name
      (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-simple "B1"))
      (should (ilist-plus--folded-p (point)))
      (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-simple "B2"))
      (should (ilist-plus--folded-p (point)))
      (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-simple "B"))
      (should-not (ilist-plus--folded-p (point)))
      (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-simple "C"))
      (should-not (ilist-plus--folded-p (point))))))

(ert-deftest ilist-plus-test-toggle-at-point ()
  (let ((imenu-list--imenu-entries ilist-plus-test--tree-simple))
    (ilist-plus-test--reset-ilist-buffer "A\n+ B\n  B1\n  B2\nC\n")
    (with-current-buffer imenu-list-buffer-name
      (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-simple "B"))
      (ilist-plus-toggle-at-point)
      (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-simple "B1"))
      (should (ilist-plus--folded-p (point)))
      (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-simple "B"))
      (ilist-plus-toggle-at-point)
      (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-simple "B1"))
      (should-not (ilist-plus--folded-p (point))))))

(ert-deftest ilist-plus-test-fold-children ()
  (let ((imenu-list--imenu-entries ilist-plus-test--tree-nested))
    (ilist-plus-test--reset-ilist-buffer "Root\n  Child1\n    GC1\n    GC2\n  Child2\n")
    (with-current-buffer imenu-list-buffer-name
      (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-nested "Root")))
    (ilist-plus-fold-children)
    (with-current-buffer imenu-list-buffer-name
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
        (let ((imenu-list--imenu-entries ilist-plus-test--tree-nested)
              (imenu-list--displayed-buffer src))
          (ilist-plus-test--reset-ilist-buffer "Root\n  Child1\n    GC1\n    GC2\n  Child2\n")
          (with-current-buffer imenu-list-buffer-name
            (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-nested "Child1"))
            (ilist-plus-toggle-at-point))
          (ilist-plus--record-folded-paths)
          (should (equal (buffer-local-value 'ilist-plus--folded-paths src)
                         '(("Root" "Child1"))))
          (ilist-plus-test--reset-ilist-buffer "Root\n  Child1\n    GC1\n    GC2\n  Child2\n")
          (with-current-buffer imenu-list-buffer-name
            (ilist-plus--restore-folded-paths (buffer-local-value 'ilist-plus--folded-paths src))
            (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-nested "GC1"))
            (should (ilist-plus--folded-p (point)))
            (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-nested "Child1"))
            (should-not (ilist-plus--folded-p (point)))))
      (kill-buffer src))))

(ert-deftest ilist-plus-test-fold-below-depth-once-dispatches-on-folded-flag ()
  (let ((src (generate-new-buffer "ilist-plus-test-src2")))
    (unwind-protect
        (let ((imenu-list--imenu-entries ilist-plus-test--tree-nested)
              (imenu-list--displayed-buffer src))
          (with-current-buffer src
            (setq-local ilist-plus--folded-once nil)
            (setq-local ilist-plus--folded-paths nil))
          (ilist-plus-test--reset-ilist-buffer "Root\n  Child1\n    GC1\n    GC2\n  Child2\n")
          (ilist-plus-fold-below-depth-once 2)
          (should (buffer-local-value 'ilist-plus--folded-once src))
          (with-current-buffer imenu-list-buffer-name
            (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-nested "GC1"))
            (should (ilist-plus--folded-p (point))))
          ;; Simulate a differing, previously-saved snapshot: the once-flag
          ;; being set must make the second call restore it verbatim rather
          ;; than recompute a fresh depth-based fold.
          (with-current-buffer src
            (setq-local ilist-plus--folded-paths '(("Root"))))
          (ilist-plus-test--reset-ilist-buffer "Root\n  Child1\n    GC1\n    GC2\n  Child2\n")
          (ilist-plus-fold-below-depth-once 2)
          (with-current-buffer imenu-list-buffer-name
            (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-nested "Child1"))
            (should (ilist-plus--folded-p (point)))
            (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-nested "GC1"))
            (should (ilist-plus--folded-p (point)))))
      (kill-buffer src))))

(ert-deftest ilist-plus-test-update-fold-markers ()
  (let ((imenu-list--imenu-entries ilist-plus-test--tree-simple))
    (ilist-plus-test--reset-ilist-buffer "A\n+ B\n  B1\n  B2\nC\n")
    (with-current-buffer imenu-list-buffer-name
      (ilist-plus-test--goto-line (ilist-plus-test--line-of ilist-plus-test--tree-simple "B"))
      (ilist-plus-toggle-at-point)
      (ilist-plus-test--goto-line 1)
      (should (equal (get-text-property (point) 'display) ilist-plus-collapsed-marker))
      (ilist-plus-toggle-at-point)
      (ilist-plus-test--goto-line 1)
      (should (equal (get-text-property (point) 'display) ilist-plus-expanded-marker)))))

(ert-deftest ilist-plus-test-rebind-buttons ()
  (ilist-plus-test--reset-ilist-buffer "hello\n")
  (with-current-buffer imenu-list-buffer-name
    (let ((ov (make-button (point-min) (point-max))))
      (should (eq (overlay-get ov 'keymap) button-map))
      (ilist-plus--rebind-buttons)
      (should (eq (overlay-get ov 'keymap) ilist-plus-button-keymap))
      (ilist-plus--rebind-buttons)
      (should (eq (overlay-get ov 'keymap) ilist-plus-button-keymap)))))

(ert-deftest ilist-plus-test-after-imenu-list-toggle-resets-locals ()
  (let ((b1 (generate-new-buffer "ilist-plus-test-b1")))
    (unwind-protect
        (progn
          (with-current-buffer b1
            (setq-local ilist-plus--folded-once t)
            (setq-local ilist-plus--folded-paths '(("x"))))
          (ilist-plus-after-imenu-list-toggle)
          (should-not (buffer-local-value 'ilist-plus--folded-once b1))
          (should-not (buffer-local-value 'ilist-plus--folded-paths b1)))
      (kill-buffer b1))))

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
  (let ((imenu-list--line-entries (list (cons "e1" 10) (cons "e2" 20) (cons "e3" 30))))
    (with-temp-buffer
      (insert (make-string 50 ?x))
      (goto-char 25)
      (should (equal (ilist-plus--current-entry) (cons "e2" 20)))))
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
            (insert ";;; Header\n\n;;; Code:\n\n;;; Section A\n\n;;;; Sub A1\n(defun test-fn-a1 () nil)\n\n;;;; Sub A2\n(defun test-fn-a2 () nil)\n"))
          (let* ((entries (with-current-buffer src (ilist-plus-elisp-index-by-position)))
                 (flat (ilist-plus--flatten-entries entries 0)))
            (with-current-buffer src
              (goto-char (point-min))
              (search-forward "test-fn-a1")
              (overlay-put (make-overlay (point) (+ (point) 5)) 'diff-hl-hunk t))
            (ilist-plus-test--reset-ilist-buffer
             (concat (mapconcat (lambda (_) "x") flat "\n") "\n"))
            (let ((imenu-list--imenu-entries entries)
                  (imenu-list--displayed-buffer src))
              (ilist-plus-highlight-modified-entries))
            (cl-labels ((marked-p (name)
                          (with-current-buffer imenu-list-buffer-name
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

(ert-deftest ilist-plus-test-skip-org-rescan-if-unmodified ()
  (let (imenu-list--imenu-entries imenu-list--displayed-buffer)
    (with-temp-buffer
      (org-mode)
      (insert "* Heading\n")
      (let ((orig-called 0))
        (cl-flet ((orig ()
                    (setq orig-called (1+ orig-called))
                    (setq imenu--index-alist '(("stub" . 1)))))
          (ilist-plus--skip-org-rescan-if-unmodified #'orig)
          (should (= orig-called 1))
          (should (equal ilist-plus--last-tick (buffer-chars-modified-tick)))
          (ilist-plus--skip-org-rescan-if-unmodified #'orig)
          (should (= orig-called 1))
          (should (eq imenu-list--imenu-entries imenu--index-alist))
          (should (eq imenu-list--displayed-buffer (current-buffer)))
          (insert "more text")
          (ilist-plus--skip-org-rescan-if-unmodified #'orig)
          (should (= orig-called 2)))))))

(provide 'ilist-plus-test)
;;; ilist-plus-test.el ends here
