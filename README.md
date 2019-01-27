# task.xq
Implementation of EXPath Tasks in pure portable XQuery 3.1.

This is a reference implementation for our paper [Task Abstraction for XPath Derived Languages. Lockett and Retter, 2019]() which
was presented at [XML Prague](http://www.xmlprague.cz) 2019.

It is worth explicitly restating that this implementation does not provide asynchronous processing, instead all asynchrnous functions will be executed synchronously.

## Using
Download the [`task.xq`]() file for use with your favourite XPDL processor.

From your main XQuery simply import the module like so:

```xquery
import module namespace task = "http://expath.org/ns/task" at "task.xq";
```

You may need to adjust the *location hint* after the `at`, refer to the documentation of your XPDL (XPath Derived Language) processor.

## Examples

### Constructing Tasks

1. Create a task from a pure value and run it
    ```xquery
    task:RUN-UNSAFE(
        task:value(1234)
    )
    ```

    1. Create a task from a pure value and run it (fluent syntax)
        ```xquery
        task:value("123") ? RUN-UNSAFE()
        ```
        
2. Create a task from a function and run it
    ```xquery
    task:RUN-UNSAFE(
        task:of(function() { 1 + 2 })
    )
    ```
    
    1. Create a task from a function and run it (fluent syntax)
        ```xquery
        task:of(function() { 1 + 2 }) ? RUN-UNSAFE()
        ```

### Composing Tasks

All examples from herein use the fluent syntax, as we believe it makes it easier for a developer to parse the intention of the code.

1. Using bind to transform a value
    ```xquery
    task:value(123)
      ?bind(function($i) { task:value($i || "val1") })
      ?bind(function($i) { task:value($i || "val2") })
      ?RUN-UNSAFE()
    ```

2. Using fmap to perform a function
    ```xquery
    task:value("hello")
        ? fmap(upper-case#1)
        ? fmap(concat(?, " adam"))
        ? RUN-UNSAFE()
    ```

3. Composing two tasks with `bind`:
    1. You should **never** have more than one call to `RUN-UNSAFE`, i.e. **DO NOT DO THIS**:
    ```xquery
    task:value("hello")
        ? fmap(upper-case#1)
        ? fmap(concat(?, " debbie"))
        ? RUN-UNSAFE()
    ,
    task:value("goodbye")
        ? fmap(upper-case#1)
        ? fmap(concat(?, " debbie"))
        ? RUN-UNSAFE()  
    ```
    
    2. Instead, you can compose the tasks with bind:
    ```xquery
    task:value("hello")
        ? fmap(upper-case#1)
        ? fmap(concat(?, " debbie"))
        ? bind(function($hello) {
            task:value("goodbye")
              ? fmap(upper-case#1)
              ? fmap(concat(?, " debbie"))
              ? fmap(function($goodbye) {($hello, $goodbye)})
        })
        ? RUN-UNSAFE() 
    ```
    
    3. The longer form if you like variable bindings:
    ```xquery
    let $task-hello := task:value("hello")
      ? fmap(upper-case#1)
      ? fmap(concat(?, " debbie"))
    
    let $task-goodbye := task:value("goodbye")
      ? fmap(upper-case#1)
      ? fmap(concat(?, " debbie"))
    
    return
      $task-hello
        ?bind(function($hello){
           $task-goodbye
             ?fmap(function($goodbye){
                ($hello, $goodbye)})})
      ? RUN-UNSAFE() 
    ```
    
    4. Or alternatively shorter syntax by partially applying `fn:insert-before` as:
    ```xquery
    task:value("hello")
        ? fmap(upper-case#1)
        ? fmap(concat(?, " debbie"))
        ? bind(function($hello) {
          task:value("goodbye")
            ? fmap(upper-case#1)
            ? fmap(concat(?, " debbie"))
            ? fmap(fn:insert-before(?, 0, $hello))
        })
        ? RUN-UNSAFE() 
    ```

    5. Or if you need an array instead of a sequence to preserve isolation of the results:
    ```xquery
    task:value("hello")
        ? fmap(upper-case#1)
        ? fmap(concat(?, " debbie"))
        ? bind(function($hello) {
            task:value("goodbye")
              ? fmap(upper-case#1)
              ? fmap(concat(?, " debbie"))
              ? fmap(function($goodbye) {[$hello, $goodbye]})
        })
        ? RUN-UNSAFE() 
    ```
    
    6. Or alternatively shorter syntax by partially applying `array:append`:
    ```xquery
    task:value("hello")
        ? fmap(upper-case#1)
        ? fmap(concat(?, " debbie"))
        ? bind(function($hello) {
            task:value("goodbye")
              ? fmap(upper-case#1)
              ? fmap(concat(?, " debbie"))
              ? fmap(array:append([$hello], ?))
        })
        ? RUN-UNSAFE() 
    ```
    
    7. The longer form for returning an array if you like variable bindings:
    ```xquery
        let $task-hello := task:value("hello")
          ? fmap(upper-case#1)
          ? fmap(concat(?, " debbie"))
        
        let $task-goodbye := task:value("goodbye")
          ? fmap(upper-case#1)
          ? fmap(concat(?, " debbie"))
        
        return
          $task-hello
            ?bind(function($hello){
               $task-goodbye
                 ?fmap(function($goodbye){
                    [$hello, $goodbye]})})
          ? RUN-UNSAFE()
    ```

4. Composing two or more tasks with `sequence`:
    1. Using the `task:sequence` function syntax:
    ```xquery
    let $task-hello := task:value("hello")
      ? fmap(upper-case#1)
      ? fmap(concat(?, " debbie"))
    
    let $task-goodbye := task:value("goodbye")
      ? fmap(upper-case#1)
      ? fmap(concat(?, " debbie"))
      ? fmap(fn:tokenize(?, " "))
      ? fmap(array:append([], ?))
    
    return
      task:sequence(($task-hello, $task-goodbye))
      ? RUN-UNSAFE()
    ```
    
    2. Using the `sequence` fluent syntax:
    ```xquery
    let $task-hello := task:value("hello")
      ? fmap(upper-case#1)
      ? fmap(concat(?, " debbie"))
      
    let $task-goodbye := task:value("goodbye")
      ? fmap(upper-case#1)
      ? fmap(concat(?, " debbie"))
      ? fmap(fn:tokenize(?, " "))
      ? fmap(array:append([], ?))
    
    return
      $task-hello
        ? sequence($task-goodbye)
        ? RUN-UNSAFE()
    ```

### Asynchronous Tasks
* Remember that an "Async" is just a reference to an asynchronous computation.

1. Asynchronously executing a task where you don't care about the result
    ```xquery
    let $some-task := task:value("hello")
      ? fmap(upper-case#1)
      ? fmap(http:post("google.com", ?))
      ? async()
    return
      $some-task ? RUN-UNSAFE()
    :)
    ```xquery

2. Asynchronously executing a task, when you do care about the result, you have to wait upon the asynchronous computation
    ```xquery
    task:value("hello")
      ? fmap(upper-case#1)
      ? async() 
      ? bind(task:wait#1)
      ? RUN-UNSAFE()
    ```

3. Asynchronous equaivalent to fork-join, where you don't care about the results :)
```xquery
let $char-to-int := function($s as xs:string) as xs:integer { fn:string-to-codepoints($s)[1] }
let $int-to-char := function($i as xs:integer) as xs:string { fn:substring(fn:codepoints-to-string($i), 1, 1) }
let $square := function($i as xs:integer) as xs:integer { $i * $i }

let $async-task1 := task:of(function(){ 1 to 10 })
  ? fmap(function($ii) { $ii ! $square(.) })
  ? async()

let $async-task2 := task:of(function(){ $char-to-int("a") to $char-to-int("z") })
  ? fmap(function($ii) { $ii ! (. - 32) })
  ? fmap(function($ii) { $ii ! $int-to-char(.)})
  ? async()
return

    $async-task1
        ?sequence($async-task2)
        ?RUN-UNSAFE()
```

4. Asynchronous equaivalent to fork-join, where you do care about the results using `task:wait-all`
```xquery
let $char-to-int := function($s as xs:string) as xs:integer { fn:string-to-codepoints($s)[1] }
let $int-to-char := function($i as xs:integer) as xs:string { fn:substring(fn:codepoints-to-string($i), 1, 1) }
let $square := function($i as xs:integer) as xs:integer { $i * $i }

let $async-task1 := task:of(function(){ 1 to 10 })
  ? fmap(function($ii) { $ii ! $square(.) })
  ? async()

let $async-task2 := task:of(function(){ $char-to-int("a") to $char-to-int("z") })
  ? fmap(function($ii) { $ii ! (. - 32) })
  ? fmap(function($ii) { $ii ! $int-to-char(.)})
  ? async()

return

  $async-task1 ?sequence($async-task2)
  ?bind(task:wait-all#1)
  ?RUN-UNSAFE()
```

5. Cancelling an asynchronous computation, and then starting another asynchronous computation
```xquery
task:value("hello")
  ? fmap(upper-case#1)
  ? async() 
  ? bind(task:cancel#1)
  ? then(task:of(function(){ (1 to 10 )}))
  ? async()
  ? bind(task:wait#1)
  ? RUN-UNSAFE()
```  

### Error Handling waith Tasks

1. Constructing an Error. No error happens, because the task has not been executed yet!
```xquery
task:of(function() {
    fn:error(xs:QName("adt:adam1"))
})
```

2. Simply constructing an Error using `task:error`.
```xquery
task:error(xs:QName("adt:adam1"), "Boom!", ())
```

3. Raises an error, beccause the task is executed! :)
```xquery
task:error(xs:QName("adt:adam1"), "Boom!", ())
  ?RUN-UNSAFE()
```

4. Using catches-recover to recover from an error
```xquery
let $local:mission-failed-err := xs:QName("local:mission-failed-err")
return

task:value("all your base...")
  ?fmap(fn:upper-case#1)
  ?fmap(fn:tokenize(?, " "))
  ?fmap(function($strings){ $strings = "BELONGS" })
  ?fmap(function($b) { if($b) then "BASES OWNED!" else fn:error($local:mission-failed-err)})
  ?catches-recover($local:mission-failed-err, function() {
    "MISSION FAILED! YOU OWN ZERO BASES!!!"
  })
  ?RUN-UNSAFE()
```
  
5. Using catch to handle any error
```xquery
let $local:mission-failed-err := xs:QName("local:mission-failed-err")
return

task:value("all your base...")
  ?fmap(fn:upper-case#1)
  ?fmap(fn:tokenize(?, " "))
  ?fmap(function($strings){ $strings = "BELONGS" })
  ?fmap(function($b) { if($b) then "BASES OWNED!" else fn:error($local:mission-failed-err)})
  ?catch(function($code, $description, $value) {
    task:value("(" || $code || ") MISSION FAILED! YOU OWN ZERO BASES!!!")
  })
  ?RUN-UNSAFE()
```
  
6. Using catch to manually handle a specific error :)
```xquery
let $local:mission-failed-err := xs:QName("local:mission-failed-err")
return
task:value("all your base...")
  ?fmap(fn:upper-case#1)
  ?fmap(fn:tokenize(?, " "))
  ?fmap(function($strings){ $strings = "BELONGS" })
  ?fmap(function($b) { if($b) then "BASES OWNED!" else fn:error($local:mission-failed-err)})
  ?catch(function($code, $description, $value) {
    if ($code eq $local:mission-failed-err) then
      task:value("MISSION FAILED! YOU OWN ZERO BASES!!!")
    else
      (: forward any other the error... :)
      task:error($code, $description, $value)
  })
  ?RUN-UNSAFE()
```

7. Using catch to handle a specific error (similar to previous, but some other error occurs earlier)
```xquery
let $local:mission-failed-err := xs:QName("local:mission-failed-err")
return
task:value("all your base...")
  ?fmap(fn:upper-case#1)
  
  (: inject some critical error :)
  ?then(task:error((), "BOOM!", ()))
  
  ?fmap(fn:tokenize(?, " "))
  ?fmap(function($strings){ $strings = "BELONGS" })
  ?fmap(function($b) { if($b) then "BASES OWNED!" else fn:error($local:mission-failed-err)})
  ?catch(function($code, $description, $value) {
    if ($code eq $local:mission-failed-err) then
      task:value("MISSION FAILED! YOU OWN ZERO BASES!!!")
    else
      (: forward any other the error... :)
      task:error($code, $description, $value)
  })
  ?RUN-UNSAFE()
```