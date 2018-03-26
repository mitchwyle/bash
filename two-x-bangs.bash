#!/usr/bin/env bash
  
function two_x_bangs () {
  originalstring=${1:-"’!!!!!!!!!’"}
  export out="${originalstring//!/!!}"
}

two_x_bangs $*
echo $out
