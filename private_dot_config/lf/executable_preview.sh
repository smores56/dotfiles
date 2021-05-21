#!/bin/bash

unset COLORTERM
bat --color always --theme $(bat-theme) "$1"
