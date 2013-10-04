;;; tree-find.el --- Find-based project explorer -*- lexical-binding: t -*-
;;; Version: 0.1
;;; Author: sabof
;;; URL: https://github.com/sabof/tree-find
;;; Package-Requires: ((cl-lib "1.0") (es-lib "0.3"))

;;; Commentary:

;; The project is hosted at https://github.com/sabof/tree-find
;; The latest version, and all the relevant information can be found there.

;;; License:

;; This file is NOT part of GNU Emacs.
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2, or (at
;; your option) any later version.
;;
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program ; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Code:

(require 'cl-lib)
(require 'es-lib)
(require 'dir-cache nil t)

(defvar tf/next-fringe nil)
(defvar tf/current-fringe nil)
(defvar tf/directory-files-function
  'tf/get-directory-files-dir-cache
  "The \"backend\" for tree-find.
  Can be a string, or a function \(WIP\).

  The string will be executed in bash, and it's output should be a
  list of files separated by newlines.

  The fucntion takes 2 arguments, and should return a list of
  files. It can also return nil - in which case you are on your
  own, as there will be no furhter processing. The arguments are
  the directory to scan, and depth. 0 means don't limit depth")

(defvar tf/project-root-function
  (lambda ()
    (if (fboundp 'projectile-project-root)
        (projectile-project-root)
      (locate-dominating-file ".git"))))

(defun tf/get-directory-files-dir-cache (dir done-func)
  (funcall done-func (dir-cache-get-dir dir)))

(defun tf/get-tree-find-buffers ()
  (es-buffers-with-mode 'tf/mode))

(cl-defun tf/revert-buffer (&rest ignore)
  (let ((inhibit-read-only t)
        (tree-find-buffer (current-buffer)))
    (erase-buffer)
    (delete-all-overlays)
    (insert "Searching for files...")
    (let (( function-result
            (funcall tf/directory-files-function
                     default-directory
                     (lambda (result)
                       (when result
                         (with-current-buffer tree-find-buffer
                           (let ((inhibit-read-only t))
                             (erase-buffer)
                             (tf/print-indented-tree
                              (tf/compress-tree
                               (tf/sort result)))
                             (tf/show-first-only)
                             (goto-char (point-min)))
                           ))))))
      )))

(cl-defun tf/compress-tree (branch)
  (cond ( (not (consp branch))
          branch)
        ( (= (length branch) 1)
          branch)
        ( (and (= (length branch) 2)
               (consp (cl-second branch)))
          (tf/compress-tree
           (cons (concat (car branch) "/" (cl-caadr branch))
                 (cl-cdadr branch))))
        ( t (cons (car branch)
                  (mapcar 'tf/compress-tree (cdr branch))))))

(cl-defun tf/sort (branch)
  (when (stringp branch)
    (cl-return-from tf/sort branch))
  (let (( new-rest
          (sort (rest branch)
                (lambda (a b)
                  (cond ( (and (consp a)
                               (stringp b))
                          t)
                        ( (and (stringp a)
                               (consp b))
                          nil)
                        ( (and (consp a) (consp b))
                          (string< (car a) (car b)))
                        ( t (string< a b)))))))
    (setcdr branch (mapcar 'tf/sort new-rest))
    branch
    ))

(cl-defun tf/print-indented-tree (branch &optional (depth -1))
  (cond ( (stringp branch)
          (insert (make-string depth ?\t)
                  branch
                  ?\n))
        ( t (when (>= depth 0)
              (insert (make-string depth ?\t)
                      (car branch) "/"
                      ?\n))
            (cl-dolist (item (rest branch))
              (tf/print-indented-tree item (1+ depth))))))

;;; TEXT ->

(defun tf/current-indnetation ()
  (- (tf/tab-ending)
     (line-beginning-position)))

(defun tf/tab-ending ()
  (save-excursion
    (goto-char (line-beginning-position))
    (skip-chars-forward "\t")
    (point)))

(cl-defun tf/unfold (expanded)
  (interactive "P")
  (save-excursion
    (let* (( point-final-pos
             (min (point)
                  (save-excursion
                    (goto-char (es-total-line-beginning))
                    (if (re-search-forward "/\n" nil t)
                        (match-beginning 0)
                      most-positive-fixnum))))
           ( initial-indentation
             (es-current-character-indentation))
           ( end (save-excursion
                   (or (tf/forward-element)
                       (goto-char (point-max)))
                   (point))))
      (remove-overlays (es-total-line-beginning-position)
                       (es-total-line-end-position)
                       'is-tf-hider t)
      (unless expanded
        (while (re-search-forward
                (concat "^"
                        (make-string (1+ initial-indentation)
                                     ?\t )
                        "[^\t\n]")
                end
                t)
          (tf/fold)))
      (goto-char point-final-pos))))

(cl-defun tf/fold ()
  (interactive)
  (when (or (looking-at ".*\n?\\'")
            (tf/folded-p))
    (cl-return-from tf/fold))
  (let* (( indent
           (save-excursion
             (goto-char (line-beginning-position))
             (skip-chars-forward "\t")
             (buffer-substring (line-beginning-position)
                               (point))))
         ( end
           (save-excursion
             (goto-char (line-end-position 1))
             (let (( regex
                     (format "^\t\\{0,%s\\}[^\t\n]"
                             (length indent))))
               ;; (setq tmp regex)
               (if (re-search-forward regex nil t)
                   (line-end-position 0)
                 (point-max)))))
         ( ov (make-overlay (line-end-position 1)
                            end)))
    (overlay-put ov 'isearch-open-invisible-temporary
                 'hs-isearch-show-temporary)
    (overlay-put ov 'isearch-open-invisible
                 'hs-isearch-show)
    (overlay-put ov 'invisible 'hs)
    (overlay-put ov 'display "...")
    (overlay-put ov 'hs 'code)
    (overlay-put ov 'is-tf-hider t)
    (overlay-put ov 'evaporate t)
    ))

(defun tf/show-first-only ()
  (interactive)
  (save-excursion
    (remove-overlays (point-min) (point-max)
                     'is-tf-hider t)
    (goto-char (point-min))
    (while (re-search-forward "^[^\t]" nil t)
      (tf/fold))))

(defun tf/up-directory ()
  (interactive)
  (setq default-directory
        (file-name-directory
         (directory-file-name
          default-directory)))
  (revert-buffer))

(defun tf/folded-p ()
  (let (( ovs (overlays-in (es-total-line-beginning-position)
                           (es-total-line-end-position))))
    (cl-some (lambda (ov)
               (overlay-get ov 'is-tf-hider))
             ovs)))

(defun tf/quit ()
  (interactive)
  (let ((window (selected-window)))
    (quit-window)
    (when (window-live-p window)
      (delete-window))))

(defun tf/forward-element (&optional arg)
  (interactive "p")
  (setq arg (or arg 1))
  (let* (( initial-indentation
           (es-current-character-indentation))
         ( regex (format "^\t\\{0,%s\\}[^\t\n]"
                         initial-indentation)))
    (if (cl-minusp arg)
        (goto-char (line-beginning-position))
      (goto-char (line-end-position)))
    (when (re-search-forward regex nil t arg)`
      (goto-char (match-end 0))
      (forward-char -1)
      )))

(defun tf/backward-element (&optional arg)
  (interactive "p")
  (setq arg (or arg 1))
  (tf/forward-element (- arg)))

(defun tf/middle-click (event)
  (interactive "e")
  (mouse-set-point event)
  (tf/return))

(defun tf/return ()
  (interactive)
  (let ((file-name (tf/get-filename)))
    (if (file-directory-p file-name)
        (tf/tab)
      (with-selected-window (cadr (window-list))
        (find-file file-name)))))

(defun tf/tab (&optional arg)
  (interactive "P")
  (if (tf/folded-p)
      (tf/unfold arg)
    (tf/fold)))

(defun tf/up-element ()
  (interactive)
  (goto-char (es-total-line-beginning-position))
  (let (( indentation (tf/current-indnetation)))
    (when  (and (not (zerop indentation))
                (re-search-backward
                 (format
                  "^\\(?1:\t\\{0,%s\\}\\)[^\t\n]"
                  (1- indentation))
                 nil t))
      (goto-char (match-end 1)))))

(defun tf/get-filename ()
  (interactive)
  (save-excursion
    (let* (( get-line-text
             (lambda ()
               (goto-char (es-total-line-beginning))
               (skip-chars-forward "\t ")
               (buffer-substring-no-properties
                (point) (line-end-position))))
           ( result
             (funcall get-line-text)))
      (while (tf/up-element)
        (setq result (concat (funcall get-line-text)
                             result)))
      (setq result (expand-file-name result))
      (when (file-directory-p result)
        (setq result (file-name-as-directory result)))
      result)))

(defun tf/find-directory (dir)
  (interactive
   (let ((file-name (tf/get-filename)))
     (list (read-file-name
            "Set directory to: "
            (if (file-directory-p file-name)
                file-name
              (file-name-directory
               (directory-file-name
                file-name)))))))
  (when (file-directory-p dir)
    (setq dir (file-name-as-directory dir)))
  (setq default-directory dir)
  (revert-buffer)
  )

(define-derived-mode tf/mode special-mode
  "Tree find"
  "Display results of find as a folding tree"
  (setq-local revert-buffer-function
              'tf/revert-buffer)
  (setq-local tab-width 2)
  (es-define-keys tf/mode-map
    (kbd "u") 'tf/up-element
    (kbd "f") 'tf/find-directory
    (kbd "<tab>") 'tf/tab
    (kbd "M-}") 'tf/forward-element
    (kbd "M-{") 'tf/backward-element
    (kbd "n") 'tf/forward-element
    (kbd "p") 'tf/backward-element
    ;; (kbd "^") 'tf/up-directory
    (kbd "<return>") 'tf/return
    (kbd "<mouse-2>") 'tf/middle-click
    (kbd "q") 'tf/quit
    (kbd "s") 'isearch-forward
    (kbd "r") 'isearch-backward
    )
  (font-lock-add-keywords
   'tf/mode '(("^.+/$" (0 'dired-directory append)))))

;;; Interface

(cl-defun tree-find-open ()
  (interactive)
  (let* (( project-root (funcall tf/project-root-function))
         ( project-tree-find-existing-buffer
           (cl-find project-root
                    (tf/get-tree-find-buffers)
                    :key (lambda (project-tree-find-buffer)
                           (with-current-buffer project-tree-find-buffer
                             default-directory))
                    :test 'string-equal))
         ( tree-find-window
           (and project-tree-find-existing-buffer
                (get-window-with-predicate
                 (lambda (tree-find-window)
                   (eq (window-buffer tree-find-window)
                       project-tree-find-existing-buffer))
                 (window-list))))
         ( project-tree-find-buffer
           (or project-tree-find-existing-buffer
               (with-current-buffer
                   (generate-new-buffer "*tree-find*")
                 (tf/mode)
                 (setq default-directory project-root)
                 (revert-buffer)
                 (setq window-size-fixed 'width)
                 (current-buffer)))))
    (when tree-find-window
      (select-window tree-find-window)
      (cl-return-from tree-find-open))

    (setq tree-find-window (split-window (frame-root-window)
                                         (- (frame-width) 40) 'left))
    (set-window-parameter tree-find-window 'window-side 'right)
    (set-window-buffer tree-find-window project-tree-find-buffer)
    (set-window-dedicated-p tree-find-window t)
    (select-window tree-find-window)
    ))


;;; tree-find.el ends here
