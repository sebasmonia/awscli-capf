;;; awscli-capf.el --- Completion at point function for the AWS CLI  -*- lexical-binding: t; -*-

;; Copyright (C) 2019 Sebastian Monia
;;
;; Author: Sebastian Monia <smonia@outlook.com>
;; URL: https://github.com/sebasmonia/awscli-capf.git
;; Package-Requires: ((emacs "26") (company "0.9.10"))
;; Version: 1.0
;; Keywords: tools convenience abbrev

;; This file is not part of GNU Emacs.

;;; License: MIT

;;; Commentary:

;; Add the function `awscli-capf' to the list of completion functions, for example:
;;
;; (require 'awscli-capf)
;; (add-hook 'shell-mode-hook (lambda ()
;;                             (add-to-list 'completion-at-point-functions 'awscli-capf)))
;;
;; or with use-package:
;;
;; (use-package awscli-capf
;;   :commands (awscli-add-to-capf)
;;   :hook (shell-mode . awscli-add-to-capf))
;;
;; For more details  see https://github.com/sebasmonia/awscli-capf/blob/master/README.md
;;
;;; Code:

(require 'cl-lib)
(require 'company)

;;(add-to-list 'completion-at-point-functions 'awscli-capf)
(defconst awscli--capf-script-dir (file-name-directory load-file-name)  "The directory from which the package loaded.")
(defconst awscli--capf-data-file (expand-file-name "awscli-capf-docs.data" awscli--capf-script-dir) "Location of the file with the help data.")
(defvar awscli--capf-services-info nil "Names and docs of all services, commands and options of the AWS CLI.")
(defvar awscli--capf-global-options-info nil "Top level options of the AWS CLI.")

(defun awscli-add-to-capf ()
  "Convenience function to invoke in a mode's hook to get AWS CLI completion.
It adds `awscli-capf' to `completion-at-point-functions'."
  (add-to-list 'completion-at-point-functions
               'awscli-capf))

(defun awscli-capf ()
  "Function for completion at point of AWS CLI services and commands.
Run \"(add-to-list 'completion-at-point-functions 'awscli-capf)\" in a mode's hook to add this completion."
  (unless awscli--capf-services-info
    (awscli--capf-read-data-from-file))
  (save-excursion
    (let* ((line (split-string (thing-at-point 'line t)))
           (bounds (bounds-of-thing-at-point 'sexp)) ;; 'word is delimited by "-" in shell modes, 'sexp is "space delimited" like we want
           (aws-command-start (position "aws" line :test #'string=))
           (service (when aws-command-start (elt line (+ 1 aws-command-start))))
           (command (when aws-command-start (elt line (+ 2 aws-command-start))))
           ;; parameters start with --, we use this to filter parameters already consumed
           (params (when aws-command-start (awscli--capf-param-strings-only (subseq line aws-command-start))))
           (service-names-docs (awscli--capf-service-completion-data)) ;; we always need the service names to confirm we have a good match
           (command-names-docs (awscli--capf-command-completion-data service)) ;; will return data for a "good" service name, or nil for a partial/invalid entry
           (candidates nil)) ;; populated in the cond below
      (message (thing-at-point 'word t))
      (when aws-command-start
        (cond ((and service (member command command-names-docs)) (setq candidates (awscli--capf-parameters-completion-data service command params)))
              ((and service (member service service-names-docs)) (setq candidates command-names-docs))
              ;; if it's an aws command but there's no match for service name, complete service
              (t (setq candidates service-names-docs)))
        (when bounds
          (list (car bounds)
                (cdr bounds)
                candidates
                :exclusive 'no
                :annotation-function #'awscli--capf-annotation
                :company-docsig #'identity
                :company-doc-buffer #'awscli--capf-help-buffer))))))

(cl-defstruct (awscli--capf-service (:constructor awscli--capf-service-create)
                               (:copier nil))
  name commands docs)

(cl-defstruct (awscli--capf-command (:constructor awscli--capf-command-create)
                               (:copier nil))
  name options docs)

(cl-defstruct (awscli--capf-option (:constructor awscli--capf-option-create)
                               (:copier nil))
  name type docs)

(defun awscli--capf-help-buffer (candidate)
  "Extract from CANDIDATE the :awsdoc text property."
  ;; this property is added to the name string in the function that gets
  ;; the completion data for `candidates'
  (company-doc-buffer (get-text-property 0 :awsdoc candidate)))

(defun awscli--capf-annotation (candidate)
  "Extract from CANDIDATE the :awsannotation text property.
Return empty string if not present."
  ;; this property is added to the name string in the function that gets
  ;; the completion data for `candidates'. So far only present for
  ;; parameters
  (let ((aws-annotation (get-text-property 0 :awsannotation candidate)))
    (or aws-annotation "")))

(defun awscli--capf-store-data-in-file (records)
  "Save RECORDS in `awscli--capf-data-file'."
  (with-temp-buffer
    (insert (prin1-to-string records))
    (write-file awscli--capf-data-file)
    (message "awscli-capf - updated completion data")))

(defun awscli--capf-read-data-from-file ()
  "Load the completion data stored in `awscli--capf-data-file'."
  (with-temp-buffer
    (insert-file-contents awscli--capf-data-file)
    (let ((all-data (read (buffer-string))))
      (setq awscli--capf-services-info (cl-first all-data))
      (setq awscli--capf-global-options-info (cl-second all-data))
      (message "awscli-capf - loaded completion data"))))

(defun awscli--capf-param-strings-only (strings)
  "Filter the list of STRINGS and keep only the ones starting with \"--\"."
  (cl-remove-if-not (lambda (str) (string-prefix-p "--" str)) strings))

(defun awscli--capf-service-completion-data ()
  "Generate the completion data for services.
The format is a string of the service name, with two extra properties, :awsdoc
and :awsannotation that contain help text for the help buffer and minibuffer, respectively."
  (mapcar (lambda (serv)
            (propertize (awscli--capf-service-name serv)
                        :awsdoc (awscli--capf-service-docs serv)
                        :awsannotation " (aws service)"))
          awscli--capf-services-info))

(defun awscli--capf-command-completion-data (service-name)
  "Generate the completion data for a SERVICE-NAME commands.
The format is a string of the command name, with a property :awsdoc that
contains the help text."
  (let ((service (cl-find service-name
                          awscli--capf-services-info
                          :test (lambda (value item)
                                  (string= (awscli--capf-service-name item) value)))))
    (when service
      (mapcar (lambda (comm)
                (propertize (awscli--capf-command-name comm)
                            :awsdoc (awscli--capf-command-docs comm)
                            :awsannotation " (aws command)"))
              (awscli--capf-service-commands service)))))

(defun awscli--capf-parameters-completion-data (service-name command-name used-params)
    "Generate the completion data for the parameters of COMMAND-NAME.
The command is searched under SERVICE-NAME.  USED-PARAMS are excluded from the
results.  The format is a string with the service name, with a property :awsdoc
that contains the parameter's type and help text."
  (let* ((service (cl-find service-name
                           awscli--capf-services-info
                           :test (lambda (value item)
                                   (string= (awscli--capf-service-name item) value))))
         (command (when service
                    (cl-find command-name
                             (awscli--capf-service-commands service)
                             :test (lambda (value item)
                                     (string= (awscli--capf-command-name item) value))))))
    (when command
      (cl-remove-if (lambda (item) (member item used-params))
                    (mapcar (lambda (opt)
                              (propertize (awscli--capf-option-name opt)
                                          :awsdoc (format "Type: %s\n\n%s"
                                                          (awscli--capf-option-type opt)
                                                          (awscli--capf-option-docs opt))
                                          :awsannotation (format " (aws param - %s)"
                                                                 (awscli--capf-option-type opt))))
                            (concatenate 'list
                                         (awscli--capf-command-options command)
                                         awscli--capf-global-options-info))))))

(defun awscli-capf-refresh-data-from-cli ()
  "Run \"aws help\" in a shell and and parse output to update cached docs.
More functions are invoked from this one to update commands and parameters."
  (interactive)
  (with-temp-buffer
    (call-process "aws" nil t nil "help")
    (goto-char (point-min))
    (let* ((case-fold-search nil)
           (opt-start (search-forward-regexp "^Options$"))
           (serv-start (search-forward-regexp "^Available Services$"))
           (serv-end (search-forward-regexp "^See Also$"))
           (global-options nil)
           (services nil))
      ;; from the "Options" title, search for all the ocurrences
      ;; of "--something-something", bound to the start of services names
      ;; and retrieve from the line the text between quotes
      (goto-char opt-start)
      (while (search-forward-regexp "^\"\\(.*?\\)\" (\\(.*?\\))\n\n\\(.*\\)" serv-start t)
        (push (awscli--capf-option-create :name (match-string 1)
                                      :type (match-string 2)
                                      :docs (match-string 3))
              global-options))
      ;; from the "Available Services" title, search for all the ocurrences
      ;; of "* something", bound to the start the "See Also" title
      ;; and retrieve from the line the text after "* "
      (goto-char serv-start)
      (while (search-forward-regexp "^* \\(.*\\)$" serv-end t)
        (let ((service-name (match-string 1)))
          (unless (string= service-name "help")
            (push (awscli--capf-service-data-from-cli service-name)
                  services))))
      (awscli--capf-store-data-in-file (list services global-options)))))

(defun awscli--capf-service-data-from-cli (service)
  "Run \"aws [SERVICE] help\" in a shell and parse output to update cached docs.
For each command in the service, more functions are called to parse command and
parameter output."
  (with-temp-buffer
    (message "Service: %s" service)
    (call-process "aws" nil t nil service "help")
    (goto-char (point-min))
    (let* ((case-fold-search nil)
           (command-start (search-forward-regexp "^Available Commands$" nil t))
           (commands nil))
      ;; from the "Available Commands" title, search for all the ocurrences
      ;; of "* something" until the end of the buffer, and retrieve
      ;; from the line the text after "* "
      (when command-start
        (goto-char command-start)
        (while (search-forward-regexp "^* \\(.*\\)$" nil t)
          (let ((command-name (match-string 1)))
            (unless (string= command-name "help") ;; yeah, skip "help"
              (push (awscli--capf-command-data-from-cli service command-name)
                    commands)))))
      ;; return the service, use the entire buffer as help string
      (awscli--capf-service-create :name service
                               :commands commands
                               :docs (buffer-string)))))

(defun awscli--capf-command-data-from-cli (service command-name)
  "Run \"aws [SERVICE] [COMMAND-NAME] help\" to update the cached docs.
This is the last level of output parsing."
  (with-temp-buffer
    (message "Service: %s Command: %s" service command-name)
    (call-process "aws" nil t nil service command-name "help")
    (goto-char (point-min))
    (let* ((case-fold-search nil)
           (opt-start (search-forward-regexp "^Options$" nil t))
           (options nil))
      ;; from the "Options" title, search for all the ocurrences
      ;; of "--something-something", bound to the start of services names
      ;; and retrieve from the line the text between quotes
      ;; some commands don't have "Options", for now we ignore them but
      ;; there's a chance that handling will be added to them
      (when opt-start
        (goto-char opt-start)
        (while (search-forward-regexp "^\"\\(.*?\\)\" (\\(.*?\\))\n\n\\(.*\\)" nil t)
          (push (awscli--capf-option-create :name (match-string 1)
                                        :type (match-string 2)
                                        :docs (match-string 3))
                options)))
      (awscli--capf-command-create :name command-name
                               :options options
                               :docs (buffer-string)))))

(provide 'awscli-capf)
;;; awscli-capf.el ends here
