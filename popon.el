;;; popon.el --- "Pop" floating text "on" a window -*- lexical-binding: t -*-

;; Copyright (C) 2022 Akib Azmain Turja.

;; Author: Akib Azmain Turja <akib@disroot.org>
;; Created: 2022-04-11
;; Version: 0.1
;; Package-Requires: ((emacs "27.1"))
;; Keywords: lisp extensions frames
;; Homepage: https://codeberg.org/akib/emacs-popon

;; This file is not part of GNU Emacs.

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; For a full copy of the GNU General Public License
;; see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Popon allows you to pop text on a window, what we call a popon.  Popons
;; are window-local and sticky, they don't move while scrolling, and they
;; even don't go away when switching buffer, but you can bind a popon to a
;; specific buffer to only show on that buffer.

;; If some popons annoying you and you can't kill them, do M-x
;; popon-kill-all to kill all popons.

;;; Code:

(require 'subr-x)
(require 'cl-lib)

(defun popon--render-lines (framebuffer x y lines width)
  "Place LINES on top of FRAMEBUFFER.
Place LINES on top of text at line X and column Y on FRAMEBUFFER and return
FRAMEBUFFER.  LINES is a list of list as string.  FRAMEBUFFER is a list,
each element is of form: (LINE MODIFIED OTHERS...), where LINE is the line
as string and MODIFIED is t when LINE is modified.  OTHERS is not modified
in any way.  Each line in LINES is assumed to occupy WIDTH character.
FRAMEBUFFER and LINES shouldn't contain newlines.  Example:

\(`popon--render-lines'
 '((\"GNU Emacs is “free software”; this means\" nil)
   (\"that everyone is free to use it and free\" nil)
   (\"to redistribute it under certain\"         nil)
   (\"conditions.  GNU Emacs is not in the\"     nil)
   (\"public domain; it is copyrighted and\"     nil)
   (\"there are restrictions on its\"            nil)
   (\"distribution, but these restrictions are\" nil)
   (\"designed to permit everything that a\"     nil foo)
   (\"good cooperating citizen would want to\"   nil bar baz)
   (\"do.  What is not allowed is to try to\"    nil)
   (\"prevent others from further sharing any\"  nil)
   (\"version of GNU Emacs that they might get\" nil)
   (\"from you.  The precise conditions are\"    nil)
   (\"found in the GNU General Public License\"  nil)
   (\"that comes with Emacs and also appears\"   nil)
   (\"in this manual(1).  See Copying.\"         t))
 11 1 '(\"+--^^^^^^^^^^^^^-------------------------+\"
        \"|Free software is a type of software that|\"
        \"|respects user freedom.  Think free as in|\"
        \"|free speech, not as in free beer.       |\"
        \"+----------------------------------------+\")
 42)
=> ((\"GNU Emacs is “free software”; this means\"              nil)
    (\"that everyo+--^^^^^^^^^^^^^-------------------------+\" t)
    (\"to redistri|Free software is a type of software that|\" t)
    (\"conditions.|respects user freedom.  Think free as in|\" t)
    (\"public doma|free speech, not as in free beer.       |\" t)
    (\"there are r+----------------------------------------+\" t)
    (\"distribution, but these restrictions are\"              nil)
    (\"designed to permit everything that a\"                  nil foo)
    (\"good cooperating citizen would want to\"                nil bar baz)
    (\"do.  What is not allowed is to try to\"                 nil)
    (\"prevent others from further sharing any\"               nil)
    (\"version of GNU Emacs that they might get\"              nil)
    (\"from you.  The precise conditions are\"                 nil)
    (\"found in the GNU General Public License\"               nil)
    (\"that comes with Emacs and also appears\"                nil)
    (\"in this manual(1).  See Copying.\"                      t))"
  (let ((tab-size tab-width))
    (with-temp-buffer
      (setq-local tab-width tab-size) ; Preseve tab width.
      (dotimes (i (length lines))
        (when (< (+ y i) (length framebuffer))
          (erase-buffer)
          (insert (car (nth (+ y i) framebuffer)))
          (move-to-column x t)
          (let ((mark (point)))
            (move-to-column (+ x width) t)
            (setf (car (nth (+ y i) framebuffer))
                  (concat (buffer-substring (point-min) mark)
                          (nth i lines)
                          (buffer-substring (point) (point-max))))
            (setf (cadr (nth (+ y i) framebuffer)) t))))
      framebuffer)))

(defun poponp (object)
  "Return t if OBJECT is a popon."
  (and (proper-list-p object)
       (eq (car-safe object) 'popon)))

(defun popon-live-p (object)
  "Return t if OBJECT is a popon and not killed."
  (and (poponp object)
       (plist-get (cdr object) :live)
       (and (plist-get (cdr object) :window)
            (window-live-p (plist-get (cdr object) :window)))
       (or (not (plist-get (cdr object) :buffer))
           (buffer-live-p (plist-get (cdr object) :buffer)))
       t))

(defun popon-get (popon prop)
  "Get the PROP property of popon POPON."
  (plist-get (plist-get (cdr popon) :plist) prop))

(defun popon-put (popon prop value)
  "Set the PROP property of popon POPON to VALUE."
  (setcdr popon (plist-put (cdr popon)
                           :plist (plist-put (plist-get (cdr popon) :plist)
                                             prop value))))

(defun popon-properties (popon)
  "Return a copy the property list of popon POPON."
  (copy-sequence (plist-get (cdr popon) :plist)))

(defun popon-position (popon)
  "Return the position of popon POPON as a cons (X, Y).

When popon POPON is killed, return nil."
  (when (popon-live-p popon)
    (cons (plist-get (cdr popon) :x)
          (plist-get (cdr popon) :y))))

(defun popon-size (popon)
  "Return the size of popon POPON as a cons (WIDTH . HEIGHT).

When popon POPON is killed, return nil."
  (when (popon-live-p popon)
    (cons (plist-get (cdr popon) :width)
          (length (plist-get (cdr popon) :lines)))))

(defun popon-window (popon)
  "Return the window popon POPON belongs to.

Return nil if popon POPON is killed."
  (when (popon-live-p popon)
    (plist-get (cdr popon) :window)))

(defun popon-buffer (popon)
  "Return the buffer popon POPON belongs to.

Return nil if popon POPON is killed."
  (when (popon-live-p popon)
    (plist-get (cdr popon) :buffer)))

(defun popon-text (popon)
  "Return the text popon POPON is displaying.

POPON may be a killed popon.  Return nil if POPON isn't a popon at all."
  (when (poponp popon)
    (mapconcat #'identity (plist-get (cdr popon) :lines) "\n")))

(defun popon--render (popon framebuffer offset)
  "Render POPON in FRAMEBUFFER at vertical offset OFFSET."
  (popon--render-lines framebuffer
                       (+ (plist-get (cdr popon) :x) offset)
                       (plist-get (cdr popon) :y)
                       (plist-get (cdr popon) :lines)
                       (plist-get (cdr popon) :width)))

(defun popon-create (text pos &optional window buffer)
  "Create a popon showing TEXT at POS of WINDOW.

Display popon only if WINDOW is displaying BUFFER.

POS is a cons (X, Y), where X is column and Y is line in WINDOW.  TEXT
should be a string or a cons cell of form (STR . WIDTH).  When TEXT is a
string, each line of it should be of same length (i.e `string-width' should
return the same length for every line).  When TEXT is a cons cell, STR is
used as the text to display and each line of it should be of visual length
width."
  (let* ((lines (split-string (if (consp text) (car text) text) "\n"))
         (popon `(popon :live t
                        :x ,(car pos)
                        :y ,(cdr pos)
                        :lines ,lines
                        :width ,(or (and (consp text) (cdr text))
                                    (string-width (car lines)))
                        :window ,(or window (selected-window))
                        :buffer ,buffer
                        :plist nil)))
    (push popon (window-parameter window 'popon-list))
    (popon-update)
    popon))

(defun popon-kill (popon)
  "Kill popon POPON.

Do nothing if POPON isn't a live popon.  Return nil."
  (when (popon-live-p popon)
    (let ((window (popon-window popon)))
      (setf (window-parameter window 'popon-list)
            (delete popon (window-parameter window 'popon-list))))
    (setcdr popon (plist-put (cdr popon) :live nil))
    (popon-update)
    nil))

(defvar-local popon--line-beginnings nil
  "List of line beginning of current buffer.

The value is of form (TICK . LINE-BEGINNINGS), where LINE-BEGINNINGS is the
sorted list of beginning of lines and TICK is the value of tick counter
when LINE-BEGINNINGS was calculated.")

(defun popon--make-framebuffer ()
  "Create a framebuffer for current window and buffer."
  (let ((framebuffer nil)
        (line-boundaries (let ((pair popon--line-beginnings)
                               (boundaries nil))
                           (when (eq (car pair) (buffer-modified-tick))
                             (setq pair (cdr pair))
                             (while pair
                               (when (and (integerp (car pair))
                                          (integerp (cadr pair)))
                                 (push (cons (car pair) (cadr pair))
                                       boundaries))
                               (setq pair (cdr pair))))
                           boundaries)))
    (save-excursion
      (goto-char (window-start))
      (let ((mark (point))
            (point-to-line nil))
        (dotimes (i (floor (window-screen-lines)))
          (if-let ((next (alist-get (point) line-boundaries)))
              (goto-char next)
            (if truncate-lines
                (forward-line 1)
              (vertical-motion 1)))
          (let ((line (alist-get mark point-to-line)))
            (unless line
              (setq line i)
              (setf (alist-get mark point-to-line) line))
            (push (list (string-trim-right (buffer-substring mark (point))
                                           "\n")
                        nil line mark (point))
                  framebuffer))
          (push (cons mark (point)) line-boundaries)
          (setq mark (point)))))
    (let ((line-beginnings nil))
      (dolist (pair (sort (cl-delete-duplicates line-boundaries
                                                :test #'equal)
                          #'car-less-than-car))
        (unless (eq (car line-beginnings) (car pair))
          (when (car line-beginnings)
            (push nil line-beginnings))
          (push (car pair) line-beginnings))
        (push (cdr pair) line-beginnings))
      (push nil line-beginnings)
      (setq popon--line-beginnings (cons (buffer-modified-tick)
                                         (nreverse line-beginnings))))
    (nreverse framebuffer)))

(defun popon--make-overlays (framebuffer)
  "Make overlays to display FRAMEBUFFER on window."
  (let ((line-map nil))
    (let ((i 0))
      (dolist (line framebuffer)
        (when (nth 1 line)
          (let* ((key (cons (nth 3 line) (nth 4 line)))
                 (pair (assoc key line-map)))
            (unless pair
              (setq pair (cons key nil))
              (push pair line-map))
            (push (cons (- i (nth 2 line)) (car line)) (cdr pair))))
        (setq i (1+ i))))
    (let ((newline-at-display t))
      (dolist (block line-map)
        (let ((ov (make-overlay (caar block) (cdar block))))
          (push ov (window-parameter nil 'popon-overlays))
          (overlay-put ov 'window (selected-window))
          (overlay-put ov 'display (if newline-at-display "\n" ""))
          (overlay-put
           ov 'before-string
           (let ((text "")
                 (current-offset 0))
             (when (and (= (caar block) (cdar block) (point-max))
                        (> (caar block) 0)
                        (not (equal (buffer-substring-no-properties
                                     (1- (caar block)) (caar block))
                                    "\n")))
               (setq text "\n"))
             (dolist (line (sort (cdr block) #'car-less-than-car))
               (setq text (concat text
                                  (make-string (- (car line)
                                                  current-offset)
                                               ?\n)
                                  (cdr line)))
               (setq current-offset (car line)))
             (add-face-text-property 0 (length text) 'default 'append text)
             (concat text (unless newline-at-display "\n"))))
          (setq newline-at-display (not newline-at-display)))))))

(defun popon--redisplay-1 (force)
  "Redisplay popon overlays.

When FORCE is non-nil, update all overlays."
  (let ((popon-available-p nil)
        (any-popon-visible-p nil))
    (dolist (frame (frame-list))
      (dolist (window (window-list frame))
        (set-window-parameter
         window 'popon-list
         (cl-remove-if-not #'popon-live-p
                           (window-parameter window 'popon-list)))
        (when (window-parameter window 'popon-list)
          (setq popon-available-p t))
        (let ((popons
               (cl-remove-if-not
                (lambda (popon)
                  (and (or (null (popon-buffer popon))
                           (eq (popon-buffer popon) (window-buffer)))
                       (< (cdr (popon-position popon))
                          (with-selected-window window
                            (floor (window-screen-lines))))
                       (< (car (popon-position popon))
                          (- (window-width window)
                             (with-selected-window window
                               (line-number-display-width))))))
                (window-parameter window 'popon-list))))
          (when (or force
                    (not
                     (and
                      (null (cl-set-difference
                             popons
                             (window-parameter window
                                               'popon-visible-popons)))
                      (null (cl-set-difference
                             (window-parameter window
                                               'popon-visible-popons)
                             popons))
                      (eq (window-parameter window 'popon-window-start)
                          (window-start window))
                      (eq (window-parameter window 'popon-window-hscroll)
                          (window-hscroll window))
                      (eq (window-parameter window 'popon-window-buffer)
                          (window-buffer window)))))
            (while (window-parameter window 'popon-overlays)
              (delete-overlay (pop (window-parameter window
                                                     'popon-overlays))))
            (with-selected-window window
              (let* ((framebuffer (popon--make-framebuffer)))
                (dolist (popon popons)
                  (popon--render popon framebuffer (window-hscroll)))
                (popon--make-overlays framebuffer)))
            (set-window-parameter window 'popon-visible-popons popons)
            (set-window-parameter window 'popon-window-start
                                  (window-start window))
            (set-window-parameter window 'popon-window-hscroll
                                  (window-hscroll window))
            (set-window-parameter window 'popon-window-buffer
                                  (window-buffer window))))
        (when (window-parameter window 'popon-visible-popons)
          (setq any-popon-visible-p t))))
    (if any-popon-visible-p
        (add-hook 'pre-redisplay-functions #'popon--pre-redisplay)
      (remove-hook 'pre-redisplay-functions #'popon--pre-redisplay))
    (if popon-available-p
        (add-hook 'window-configuration-change-hook #'popon-update)
      (remove-hook 'window-configuration-change-hook #'popon-update))))

(defun popon-redisplay ()
  "Redisplay popon overlays."
  (popon--redisplay-1 t))

(defun popon-update ()
  "Update popons if needed."
  (popon--redisplay-1 nil))

(defun popon--pre-redisplay (_)
  "Update popons."
  (popon-update))

(defun popon-x-y-at-pos (point)
  "Return the (X, Y) coodinate of POINT in selected window as a cons cell.

Return nil if POINT is not in visible text area.

NOTE: This uses `posn-at-point', which is slow.  So try to minimize calls
to this function."
  (let ((window-start-x-y (posn-col-row (posn-at-point (window-start))))
        (point-x-y (posn-col-row (posn-at-point point))))
    (cons (- (car point-x-y) (car window-start-x-y))
          (- (cdr point-x-y) (cdr window-start-x-y)))))

(defun popon-kill-all ()
  "Kill all popons."
  (interactive)
  (dolist (frame (frame-list))
    (dolist (window (window-list frame))
      (while (window-parameter window 'popon-list)
        (popon-kill (pop (window-parameter window 'popon-list)))))))

(provide 'popon)
;;; popon.el ends here
