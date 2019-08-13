# AWS CLI - Completion at point

The AWS command line tool has a support for all of Amazon services, with tens of commands for each one.
I thought about creating a wrapper for it using for example Transient. But with so many commands, it seemed too daunting a task.
Plus, I'm not familiarized with all of them. I don't think anyone has used all of them!  

But what if, instead, we could have support for completion, with quick access to the vast documentation in the tool? Then when you type
`aws` in your shell buffer, completion at point would suggest valid commands. And by leveraging some company-mode extensions, the docs
are one `C-h` away!

## Table of contents

<!--ts-->

   * [Installation and configuration](#installation-and-configuration)
   * [Refreshing completion data](#refreshing-completion-data)
   * [Adding to a mode](#adding-to-a-mode)

<!--te-->

## Installation and configuration

Place awscli-capf.el and optionally awscli-capf-docs.el in your load-path. (MELPA submission coming soon).

## Refreshing completion data

If you don't want to use the pre-generated completion data in awscli-capf-docs.el, then after loading `awscli-capf` 
you can invoke the command `accapf-refresh-data-from-cli`.
This command will run `aws help` and use regular expressions to go over the output and get the list of services.
Then for each service it will execute `aws [service] help` and so on for each combination of service and command.

This can take quite a while! And it's the less robust part of the process, to be honest. If in the future the documentation
format changes, the functions parsing the output will need to be adjusted.

## Adding to a mode

Just add the function `awscli-capf` to the list of completion functions, for example:

```
(add-hook 'shell-mode-hook (lambda ()
                             (add-to-list 'completion-at-point-functions 'awscli-capf)))
```

## Screenshoots

(Coming soon)
