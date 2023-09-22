## Installation

1. Run ./scripts/create_cert_and_keys.sh
2. Build images
3. Run containers

## Docs envsubst

|__Expression__     | __Meaning__    |
| ----------------- | -------------- |
|`${var}`           | Value of var (same as `$var`)
|`${var-$DEFAULT}`  | If var not set, evaluate expression as $DEFAULT
|`${var:-$DEFAULT}` | If var not set or is empty, evaluate expression as $DEFAULT
|`${var=$DEFAULT}`  | If var not set, evaluate expression as $DEFAULT
|`${var:=$DEFAULT}` | If var not set or is empty, evaluate expression as $DEFAULT
|`${var+$OTHER}`    | If var set, evaluate expression as $OTHER, otherwise as empty string
|`${var:+$OTHER}`   | If var set, evaluate expression as $OTHER, otherwise as empty string
|`$$var`            | Escape expressions. Result will be `$var`. 

<sub>Most of the rows in this table were taken from [here](http://www.tldp.org/LDP/abs/html/refcards.html#AEN22728)</sub>
