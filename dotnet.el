;;; dotnet.el --- Interact with dotnet CLI tool

;; Copyright (C) 2018 by Julien Blanchard

;; Author: Julien BLANCHARD <julien@sideburns.eu>
;; URL: https://github.com/julienXX/dotnet.el
;; Version: 0.4
;; Keywords: .net, tools

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; dotnet CLI minor mode.

;; Provides some key combinations to interact with dotnet CLI.

;;; Code:

(defgroup dotnet nil
  "dotnet group."
  :prefix "dotnet-"
  :group 'tools)

(defcustom dotnet-mode-keymap-prefix (kbd "C-c C-n")
  "Dotnet minor mode keymap prefix."
  :group 'dotnet
  :type 'string)

(defcustom dotnet-mode-verbosity-level "normal"
  "Verbosity level used when invoking the dotnet executable.
Check the documentation of your version of dotnet for valid values. \"diag\" is useful for troubleshooting."
  :group 'dotnet
  :type 'string)

(defvar dotnet-langs '("c#" "f#") "Languages supported by this package.")
(defvar dotnet-templates '("console" "classlib" "mstest" "xunit" "web" "mvc" "webapi") "List of dotnet project templates supported by this package.")
;; Using "" as a default instead of nil.  Then we can call string-suffix-p without ceremony.
(defvar dotnet-current-target "" "The solution/project on which the next command will operate.")
(defvar dotnet-command-log-buffer-name "*dotnet commands*" "History of dotnet commands executed")

(defvar dotnet-test-last-test-proj nil
  "Last unit test project file executed by `dotnet-test'.")

(defun dotnet--log-command (cmd-string)
  "Append CMD-STRING to the log buffer."
  (let ((log-buffer (get-buffer-create dotnet-command-log-buffer-name)))
    (with-current-buffer log-buffer
      (goto-char (point-max))
      (insert cmd-string)
      (insert "\n"))))

(defun dotnet--current-target-or-prompt ()
  "Return the current target or prompt for one.  With prefix arg prompt anyway."
  (when (or current-prefix-arg
            (string= dotnet-current-target ""))
    (setq dotnet-current-target (dotnet--select-project-or-solution)))
  dotnet-current-target)

(defun dotnet--current-target-or-prompt-sln-only ()
  "Return the current target or prompt for one, only if it's a solution.
With prefix arg prompt anyway."
  (dotnet--keep-target-if-solution)
  (when (or current-prefix-arg
            (string= dotnet-current-target ""))
    (setq dotnet-current-target (dotnet--select-project-or-solution t)))
  dotnet-current-target)

(defun dotnet--keep-target-if-project ()
  "Keep current target only if it is a project."
  (unless (string-suffix-p ".csproj" dotnet-current-target)
    (setq dotnet-current-target "")))

(defun dotnet--keep-target-if-solution ()
  "Keep current target only if it is a solution."
p  (unless (string-suffix-p ".sln" dotnet-current-target)
    (setq dotnet-current-target "")))

(defun dotnet--select-project-or-solution (&optional sln-only)
  "Prompt for the project/solution file.  Try projectile root first, else use current buffer's directory.
When SLN-ONLY allow only solutions."
  (let ((default-dir-prompt default-directory)
        (filter-regex (if sln-only
                    "\\.sln$"
                  "\\.csproj$\\|\\.sln$")))
    (ignore-errors
      (when (and (fboundp 'projectile-project-root)
                 (projectile-project-root))
        (setq default-dir-prompt (projectile-project-root))))
    (expand-file-name (completing-read
                       "Project or solution: "
                       (directory-files-recursively default-dir-prompt filter-regex)))))

(defun dotnet--verbosity-param ()
  "Return the verbosity parameter to append where applicable."
  (format "-v %s" dotnet-mode-verbosity-level))

;;;###autoload
(defun dotnet-add-package (package-name)
  "Add package reference from PACKAGE-NAME."
  (interactive "sPackage name: ")
  (dotnet--keep-target-if-project)
  (dotnet-targeted-command (concat "dotnet add %s package " (shell-quote-argument package-name))))

;;;###autoload
(defun dotnet-add-project-reference (reference)
  "Add a REFERENCE to a project."
  (interactive (list (read-file-name "Reference file: ")))
  (dotnet--keep-target-if-project)
  (dotnet-targeted-command (concat "dotnet add %s reference "  (shell-quote-argument reference))))

;;;###autoload
(defun dotnet-build ()
  "Build a .NET project."
  (interactive)
  (let* ((target (dotnet--select-project-or-solution))
         (command (concat "dotnet build " (dotnet--verbosity-param)  " %s")))
    (compile (format command target))))

;;;###autoload
(defun dotnet-clean ()
  "Clean build output."
  (interactive)
  (dotnet-targeted-command (format "dotnet clean %s %%s" (dotnet--verbosity-param))))

;;;###autoload
(defun dotnet-new (project-path template lang)
  "Initialize a new console .NET project.
PROJECT-PATH is the path to the new project, TEMPLATE is a
template (see `dotnet-templates'), and LANG is a supported
language (see `dotnet-langs')."
  (interactive (list (read-directory-name "Project path: ")
                     (completing-read "Choose a template: " dotnet-templates)
                     (completing-read "Choose a language: " dotnet-langs)))
  (dotnet-command (concat "dotnet "
                          (mapconcat 'shell-quote-argument
                                     (list "new" template  "-o" project-path "-lang" lang)
                                     " "))))

;;;###autoload
(defun dotnet-publish ()
  "Publish a .NET project for deployment."
  (interactive)
  (dotnet-targeted-command (format "dotnet publish %s %%s " (dotnet--verbosity-param))))

;;;###autoload
(defun dotnet-restore ()
  "Restore dependencies specified in the .NET project."
  (interactive)
  (dotnet-targeted-command (format "dotnet restore %s %%s " (dotnet--verbosity-param))))

;;;###autoload
(defun dotnet-run ()
  "Compile and execute a .NET project."
  (interactive)
  (dotnet--keep-target-if-project)
  (dotnet-targeted-command (format "dotnet run  %s --project %%s " (dotnet--verbosity-param))))

;;;###autoload
(defun dotnet-run-with-args (args)
  "Compile and execute a .NET project with ARGS."
  (interactive "Arguments: ")
  (dotnet-command (concat "dotnet run " args)))

;;;###autoload
(defun dotnet-sln-add ()
  "Add a project to a Solution."
  (interactive)
  (let ((solution-file (dotnet--current-target-or-prompt-sln-only))
        (to-add (read-file-name "Project/Pattern to add to the solution: ")))
    (dotnet-command (concat "dotnet sln " (shell-quote-argument solution-file) " add " to-add))))

;;;###autoload
(defun dotnet-sln-remove ()
  "Remove a project from a Solution."
  (interactive)
  (let ((solution-file (dotnet--current-target-or-prompt-sln-only))
        (to-remove (read-file-name "Project/Pattern to remove from the solution: ")))
    (dotnet-command (concat "dotnet sln " (shell-quote-argument solution-file) " remove " to-remove))))

;;;###autoload
(defun dotnet-sln-list ()
  "List all projects in a Solution."
  (interactive)
  (let ((solution-file (dotnet--current-target-or-prompt-sln-only)))
    (dotnet-command (concat "dotnet sln " (shell-quote-argument solution-file) " list"))))

;;;###autoload
(defun dotnet-sln-new ()
  "Create a new Solution."
  (interactive)
  (let ((solution-path (read-directory-name "Solution path: ")))
    (dotnet-command (concat "dotnet new sln -o " solution-path))))

;;;###autoload
(defun dotnet-test (arg)
  "Launch project unit-tests, querying for a project on first call.  With ARG, query for project path again."
  (interactive "P")
  (when (or (not dotnet-test-last-test-proj) arg)
    (setq dotnet-test-last-test-proj (dotnet--select-project-or-solution)))
  (dotnet-command (format "dotnet test %s %s" (dotnet--verbosity-param) (shell-quote-argument dotnet-test-last-test-proj))))

(defun dotnet-command (cmd)
  "Run CMD in an async buffer."
  (dotnet--log-command (concat "dotnet-command @ " default-directory))
  (dotnet--log-command cmd)
  (async-shell-command cmd "*dotnet*"))

(defun dotnet-targeted-command (cmd-to-format)
  "Run CMD-TO-FORMAT in an async buffer, with a project/solution target replaced in."
  (let* ((target (dotnet--current-target-or-prompt))
         (default-directory (file-name-directory target))
         (cmd-string (format cmd-to-format (shell-quote-argument target))))
    (dotnet--log-command (concat "dotnet-targeted-command @ " default-directory))
    (dotnet--log-command cmd-string)
    (async-shell-command cmd-string "*dotnet*")))

(defvar dotnet-mode-command-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "a p") #'dotnet-add-package)
    (define-key map (kbd "a r") #'dotnet-add-reference)
    (define-key map (kbd "b")   #'dotnet-build)
    (define-key map (kbd "c")   #'dotnet-clean)
    (define-key map (kbd "n")   #'dotnet-new)
    (define-key map (kbd "p")   #'dotnet-publish)
    (define-key map (kbd "r")   #'dotnet-restore)
    (define-key map (kbd "e")   #'dotnet-run)
    (define-key map (kbd "C-e") #'dotnet-run-with-args)
    (define-key map (kbd "s a") #'dotnet-sln-add)
    (define-key map (kbd "s l") #'dotnet-sln-list)
    (define-key map (kbd "s n") #'dotnet-sln-new)
    (define-key map (kbd "s r") #'dotnet-sln-remove)
    (define-key map (kbd "t")   #'dotnet-test)
    map)
  "Keymap for dotnet-mode commands after `dotnet-mode-keymap-prefix'.")

(defvar dotnet-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd dotnet-mode-keymap-prefix) dotnet-mode-command-map)
    map)
  "Keymap for dotnet-mode.")

;;;###autoload
(define-minor-mode dotnet-mode
  "dotnet CLI minor mode."
  nil
  " dotnet"
  dotnet-mode-map
  :group 'dotnet)


(provide 'dotnet)
;;; dotnet.el ends here
