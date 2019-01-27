xquery version "3.1";

module namespace task = "http://expath.org/ns/task";

declare namespace adt = "http://expath.org/ns/task/adt";

declare namespace array = "http://www.w3.org/2005/xpath-functions/array";
declare namespace err = "http://www.w3.org/2005/xqt-errors";
declare namespace fn = "http://www.w3.org/2005/xpath-functions";
declare namespace map = "http://www.w3.org/2005/xpath-functions/map";
declare namespace xs = "http://www.w3.org/2001/XMLSchema";

(:~
 : Reference implementation of the EXPath Task Module
 : written in XQuery.
 :
 : Note that with this reference implementation, any
 : asynchronous actions will be executed synchronously!
 : For a true implementation of this module which
 : supports asynchronous execution, support is required
 : from the XQuery processor.
 :
 : The type of a `Task` is: map(xs:string, function(*))
 :
 : The type of an `Async` function(<adt:scheduler/>) as item()+
 :
 : @author Adam Retter <adam@evolvedbinary.com>
 :)

(:~
 : Internal implementation!
 :
 : Just a helper function which creates a Map of ancillary error information
 :)
declare %private function task:err-value-map($value as item()*, $module as xs:string?, $line-number as xs:integer?, $column-number as xs:integer?, $additional as item()*) as map(xs:QName, item()*) {
  map:merge((
    if(empty($value))then () else map:entry(xs:QName("err:value"), $value),
    if(empty($module))then () else map:entry(xs:QName("err:module"), $module),
    if(empty($line-number))then () else map:entry(xs:QName("err:line-number"), $line-number),
    if(empty($column-number)) then () else map:entry(xs:QName("err:column-number"), $column-number),
    if(empty($additional)) then () else map:entry(xs:QName("err:additional"), $additional)
  ))
};

(:~
 : Internal implementation!
 :
 : Creates a representation of a Task.
 :
 : @param $apply-fn This is the real task abstraction! A function that when applied to the real world, return a (new) real world and the result of the task.
 :
 : @return A map which encapsulates operations that can be performed on a Task.
 :)
declare %private function task:create-monadic-task($apply-fn as function(element(adt:realworld)) as item()+) as map(xs:string, function(*)) {
  map {
    'apply': $apply-fn,

    'bind' : function($binder as function(item()*) as map(xs:string, function(*))) as map(xs:string, function(*)) {
      let $bound-apply-fn := function($realworld) {
        let $io-res := $apply-fn($realworld)
        return
          $binder(fn:tail($io-res))?apply(fn:head($io-res))
      }
      return
        task:create-monadic-task($bound-apply-fn)
    },

    'then': function($next as map(xs:string, function(*))) as map(xs:string, function(*)) {
      let $then-apply-fn := function($realworld) {
        let $io-res := $apply-fn($realworld)
        (: NOTE: the result given by fn:tail($io-res)
          is not needed by `then`, so we can ignore it :)
        return
          $next?apply(fn:head($io-res))
      }
      return
        task:create-monadic-task($then-apply-fn)
    },

    'liftM1': function($f as function(item()*) as item()*) as map(xs:string, function(*)) {
      let $lift-apply-fn := function($realworld) as item()+ {
        let $io-res := $apply-fn($realworld)
        return
          (fn:head($io-res), $f(fn:tail($io-res)))
      }
      return
        task:create-monadic-task($lift-apply-fn)
    },

    'liftM0': function($f as function() as item()*) as map(xs:string, function(*)) {
       let $lift-apply-fn := function($realworld) {
        let $io-res := $apply-fn($realworld)
        (: NOTE: the result given by fn:head($io-res)
          is not needed by `liftM0`, so we can ignore it :)
        return
          (fn:head($io-res), $f())
      }
      return
        task:create-monadic-task($lift-apply-fn)
    },

    'fmap': function($mapper as function(item()*) as item()*) as map(xs:string, function(*)) {
      let $fmap-apply-fn := function($realworld as element(adt:realworld)) as item()+ {
        let $io-res := $apply-fn($realworld)
        return
          (fn:head($io-res), $mapper(fn:tail($io-res)))
      }
      return
        task:create-monadic-task($fmap-apply-fn)
    },

    'sequence': function($tasks as map(xs:string, function(*))+) as map(xs:string, function(*)) {
      let $sequence-apply-fn := function($realworld as element(adt:realworld)) as item() + {
        let $io-res := $apply-fn($realworld)
        return
          task:sequence-recursive-apply(fn:head($io-res), $tasks, [fn:tail($io-res)])
      }
      return
        task:create-monadic-task($sequence-apply-fn)
    },

    'async': function() as map(xs:string, function(*)) {
      let $async-apply-fn := function($realworld as element(adt:realworld)) as item() + {

        val my-promise = new Promise(function(resolve, reject) {
        
            try {
                let $exec-NO-async := $apply-fn($realworld)
                return
                    resolve($exec-NO-async)
            } catch * {
                reject($err:code)
            }
        
        });
        
        (:
        let $exec-NO-async := $apply-fn($realworld)
        :)
        
        let $async-a := function($scheduler as element(adt:scheduler)) as item()+ {
                ($scheduler, my-promise (:fn:tail($exec-NO-async):))
        }
        
        
        return
          (: NOTE - we use $realworld and NOT fn:head($exec-NO-async) as
          the realworld in the return, because our (theoretically) asynchronously
          executing code cannot return a real world to us :)
          ($realworld, $async-a)
      }
      return
        task:create-monadic-task($async-apply-fn)
    },

    (:~
     : Creates a Task which handles an error.
     :
     : In Haskell this is similar to `catch`.
     :
     : In Scala Monix this would be similar to `onErrorHandleWith`.
     :
     : In formal descriptive terms this is:
     : <pre>
     : catches :: ((code, description, value) -> Task a) -> Task a
     : </pre>
     :
     : @param catch the function that processes the error and returns a new Task.
     :
     : @return a Task which handles the prescribed errors and returns
     :         the result of the catch.
     :)
    'catch': function($catch as function(xs:QName?, xs:string, map(*)) as map(xs:string, function(*))) as map(xs:string, function(*)) {
      let $catch-apply-fn := function($realworld as element(adt:realworld)) as item() + {
        try {
          $apply-fn($realworld)
        } catch * {
          let $catch-res := $catch($err:code, $err:description, task:err-value-map($err:value, $err:module, $err:line-number, $err:column-number, $err:additional))
          return
            $catch-res?apply($realworld)
        }
      }
      return
        task:create-monadic-task($catch-apply-fn)
    },
    
    (:~
     : Creates a Task which catches specific errors.
     :
     : Similar to `catches` but it also passes the error
     : details to the handler.
     :
     : In Haskell this is similar to `catches`.
     :
     : In Scala Monix this would be similar to `onErrorHandle`.
     :
     : In formal descriptive terms this is:
     : <pre>
     : catches :: ([code], (code, description, value) -> a) -> Task a
     : </pre>
     :
     : @param codes the errors to catch, or all errors if an empty sequence.
     : @handler a function that is evaluated when one of the specified
     :         error `codes` is raised, the handler receives the details
     :         of the error.
     :
     : @return a Task which handles the prescribed errors and returns
     :         the result of the handler   
     :)
    'catches': function($codes as xs:QName*, $handler as function(xs:QName?, xs:string, map(xs:QName, item()*)?) as item()*) as map(xs:string, function(*)) {
      let $catches-apply-fn := function($realworld as element(adt:realworld)) as item() + {
        try {
          $apply-fn($realworld)
        } catch * {
          let $err-value-map :=  task:err-value-map($err:value, $err:module, $err:line-number, $err:column-number, $err:additional)
          return
            (: only handle those errors we are interested in :)
            if (empty($codes) or $err:code = $codes) then
              ($realworld, $handler($err:code, $err:description, $err-value-map))
            else
              (: otherwise re-raise the error :)
              fn:error($err:code, $err:description, $err-value-map)
        }
      }
      return
        task:create-monadic-task($catches-apply-fn)
    },
    
    (:~
     : Creates a Task which catches specific errors.
     :
     : In Haskell this is similar to `catches` but does
     : not pass the error details to the handler.
     :
     : In Scala Monix this would be similar to `onErrorRecover`.
     :
     : In formal descriptive terms this is:
     : <pre>
     : catches-recover :: ([code], () -> a) -> Task a
     : </pre>
     :
     : @param codes the errors to catch, or all errors if an empty sequence.
     : @handler a function that is evaluated when one of the specified
     :         error `codes` is raised.
     :
     : @return a Task which handles the prescribed errors and returns
     :         the result of the handler   
     :)
    'catches-recover': function($codes as xs:QName*, $handler as function() as item()*) as map(xs:string, function(*)) {
      let $catches-apply-fn := function($realworld as element(adt:realworld)) as item() + {
        try {
          $apply-fn($realworld)
        } catch * {
          (: only handle those errors we are interested in :)
          if (empty($codes) or $err:code = $codes) then
            ($realworld, $handler())
          else
            (: otherwise re-raise the error :)
            fn:error($err:code, $err:description, task:err-value-map($err:value, $err:module, $err:line-number, $err:column-number, $err:additional))
        }
      }
      return
        task:create-monadic-task($catches-apply-fn)
    },

    'RUN-UNSAFE': function() as item()* {
      (: THIS IS THE DEVIL's WORK! :)
      fn:tail(
        $apply-fn(<adt:realworld/>)
      )
    }
  }
};


(:~ 
 : Creates a Task from a "pure" value.
 :
 : In Haskell this would be known as `return`
 : or sometimes alternatively `unit`.
 :
 : In Scala Monix this would be known as `now`
 : or `pure`.
 :
 : In formal descriptive terms this is:
 : <pre>
 : value :: a -> Task a
 : </pre>
 :
 : @param a pure value
 :
 : @return a Task which when executed returns the pure value.
 :)
declare function task:value($v as item()*) as map(xs:string, function(*)) {
  task:create-monadic-task(function($realworld) {
    ($realworld, $v)
  })
};

(:~ 
 : Creates a Task from a function.
 :
 : This allows you to wrap a potentially
 : non-pure function and delay its execution
 : until the Task is executed.
 :
 : In Haskell there is no direct equivalent.
 :
 : In Scala Monix this would be known as `eval`
 : or `delay`.
 :
 : In formal descriptive terms this is:
 : <pre>
 : of :: (() -> a) -> Task a
 : </pre>
 :
 : @param a zero arity function
 :
 : @return a Task which when executed returns the pure value.
 :)
declare function task:of($f as function() as item()*) as map(xs:string, function(*)) {
  task:create-monadic-task(function($realworld) {
    ($realworld, $f())
  })
};

(:~ 
 : Creates a Task that raises an error.
 :
 : Basically a Task abstraction for fn:error
 :
 : In Haskell this would be closest to `fail`.
 :
 : In Scala Monix this would be known as `raiseError`.
 :
 : In formal descriptive terms this is:
 : <pre>
 : error :: (code, description, error-object) -> Task none
 : </pre>
 :
 : @param $code is an error code that distinguishes this error from others.
 : @param $description is a natural-language description of the error condition.
 : @param $error-object is an arbitrary value used to convey additional
 :         information about the error, and may be used in any way the application chooses. 
 :
 : @return a Task which when executed raises the error.
 :)
declare function task:error($code as xs:QName?, $description as xs:string, $error-object as map(xs:QName, item()*)?) as map(xs:string, function(*)) {
  task:of(function() {
    fn:error($code, $description, $error-object)
  })
};

(:~
 : Internal implementation!
 :
 : Helper function for task:sequence or ?sequence.
 : Given a sequence of tasks, each task will be evaluated
 : in order with the real world progressing from one to the
 : next.
 :
 : @param $realworld a representation of the real world
 : @param $tasks the tasks to execute sequentially
 : @param $results a workspace where results are accumulated through recursion
 :
 : @return a sequence, the first item is the new real world, the second item
 :         is an array with one entry for each task result, in the same order
 :         as the tasks.
 :)
declare %private function task:sequence-recursive-apply($realworld as element(adt:realworld), $tasks as map(xs:string, function(*))*, $results as array(*)) as item()+ {
  
  (: TODO rewrite in a tail recursive form for stack-safety/performance purposes :)
  if (empty($tasks)) then
    ($realworld, $results)
  else
    let $io-res := fn:head($tasks) ?apply($realworld)
    return
      task:sequence-recursive-apply(fn:head($io-res), fn:tail($tasks), array:append($results, fn:tail($io-res)))
};

(:~ 
 : Creates a new Task representating the sequential
 : application of several other tasks.
 :
 : When the resultant task is executed, each of the provided
 : tasks will be executed sequentially, and the results returned
 : as an array.
 :
 : In both Haskell and Scala Monix this is also
 : known as `sequence`.
 :
 : In formal descriptive terms this is:
 : <pre>
 : sequence :: [Task a] -> Task [a]
 : </pre>
 :
 : @param $tasks the tasks to execute sequentially
 :
 : @return A new Task representing the sequential execution of the tasks.
 :)
declare function task:sequence($tasks as map(xs:string, function(*))+) as map(xs:string, function(*)) {
  task:create-monadic-task(function($realworld) {
     task:sequence-recursive-apply($realworld, $tasks, [])
  })
};

(:~
 : Given an Async this function will
 : extract its value and return a Task of the value.
 :
 : If the Asynchronous computation represented
 : by the Async has not yet completed,
 : then this function will block until the
 : Asynchronous computation completes.
 :
 : In Haskell this is known as `wait` in
 : the `Control.Concurrent.Async` module.
 :
 : In formal descriptive terms this is:
 : <pre>
 : wait :: Async a -> Task a
 : </pre>
 :
 : @param $async the asynchronous computation
 :
 : @return A new Task representing the result of the completed
 :     asynchronous computation.
 :)
declare function task:wait($async as function(element(adt:scheduler)) as item()+) as map(xs:string, function(*)) {
  let $wait-apply-fn := function($realworld as element(adt:realworld)) as item()+ {
    let $async-res := $async(<adt:scheduler/>)
    return
        
        (: $async-res is your actual JavaScript promise, created in async :)
        let $result := await $async-res
    
      ($realworld, $result  (:fn:tail($async-res) :))
  }
  return
    task:create-monadic-task($wait-apply-fn)
};

(:~
 : Given multiple Asyncs this function will
 : extract their values and return a Task of the values.
 :
 : If any of the Asynchronous computations represented
 : by the Asyncs have not yet completed,
 : then this function will block until all of the
 : Asynchronous computations have completed.
 :
 : In Haskell there is no direct equivalent, but can
 : be modelled by a combination of `wait` and `sequence`.
 :
 : In formal descriptive terms this is:
 : <pre>
 : wait-all :: [Async a] -> Task [a]
 : </pre>
 :
 : @param $asyncs the asynchronous computations
 :
 : @return A new Task representing the result of the completed
 :     asynchronous computations.
 :)
declare function task:wait-all($asyncs as array(function(element(adt:scheduler)) as item()+)) as map(xs:string, function(*)) {
  let $wait-all-apply-fn := function($realworld as element(adt:realworld)) as item()+ {
     let $scheduler := <adt:scheduler/> (: all were executed on the same (imaginary) scheduler :)
     let $asyncs-res := array:for-each(array:for-each($asyncs, fn:apply(?, [$scheduler])),
       fn:tail#1) (: fn:tail is used to drop the <adt:scheduler/>s :)
     return
       ($realworld, $asyncs-res)
  }
  return
    task:create-monadic-task($wait-all-apply-fn)
};

(:~
 : Given an Async this function will
 : attempt to cancel the asynchronous process.
 :
 : This is a best effort approach. There is no guarantee that the
 : asynchronous process will obey cancellation.
 :
 : If the Asynchronous computation represented
 : by the Async has already completed,
 : then no cancellation will occur.
 :
 : In Haskell this is known as `cancel` in
 : the `Control.Concurrent.Async` module.
 :
 : In Scala Monix this is known as `cancel`.
 :
 : In formal descriptive terms this is:
 : <pre>
 : cancel :: Async a -> Task ()
 : </pre>
 :
 : @param $async the asynchronous computation
 :
 : @return A new Task representing the action to cancel
 :         an asynchronous computation.
 :)
declare function task:cancel($async as function(element(adt:scheduler)) as item()+) as map(xs:string, function(*)) {
  let $cancel-apply-fn := function($realworld as element(adt:realworld)) as item()+ {
    (: we can't implement this propely in XQuery... but as the async will have
      already executed synchronously as our XQuery implementation
      is purely synchronous... we don't really have to do anything here! :)
      ($realworld, ())
  }
  return
    task:create-monadic-task($cancel-apply-fn)
};

(:~
 : Given multiple Asyncs this function will
 : attempt to cancel all of the asnchronous processes.
 :
 : This is a best effort approach. There is no guarantee that any
 : asynchronous process will obey cancellation.
 :
 : If any of the the Asynchronous computations represented
 : by the Asyncs have already completed,
 : then those will not be cancelled.
 :
 : In Haskell there is no direct equivalent, but can
 : be modelled by a combination of `cancel` and  `sequence`. 
 :
 : Likewise in Scala Monix this is no direct equivalent but
 : it can be modelled by a combination of `map` and `cancel`.
 :
 : In formal descriptive terms this is:
 : <pre>
 : cancel :: [Async a] -> Task ()
 : </pre>
 :
 : @param $asyncs the asynchronous computations
 :
 : @return A new Task representing the action to cancel
 :         the asynchronous computations.
 :)
declare function task:cancel-all($asyncs as array(function(element(adt:scheduler)) as item()+)) as map(xs:string, function(*)) {
  let $cancel-all-apply-fn := function($realworld as element(adt:realworld)) as item()+ {
     (: we can't implement this propely in XQuery... but as the async will have
      already executed synchronously as our XQuery implementation
      is purely synchronous... we don't really have to do anything here! :)
       ($realworld, ())
  }
  return
    task:create-monadic-task($cancel-all-apply-fn)
};

(:~
 : Executes a Task.
 :
 : WARNING - there should only be one of there
 :           in your application. It should likely
 :           be the last expression in your application.
 : 
 :           This function reveals non-determinism if the actions
 :           that it encapsulates are non-deterministic!
 :
 : In Haskell the equivalent is `unsafePerformIO`.
 :
 : In Scala Monix this would be known as `runSyncUnsafe`.
 :
 : In formal descriptive terms this is:
 : <pre>
 : RUN-UNSAFE :: Task a -> a
 : </pre> 
 :
 : @param The task to execute
 :
 : @return The result of the task
 :)
declare function task:RUN-UNSAFE($task as map(xs:string, function(*))) {
 fn:tail($task
   ? apply(<adt:realworld/>)
 )
};
