// Written in the D programming language.

/++
    This module defines functions related to exceptions and general error
    handling. It also defines functions intended to aid in unit testing.

    Synopsis of some of std.exception's functions:
--------------------
string synopsis()
{
   FILE* f = enforce(fopen("some/file"));
   // f is not null from here on
   FILE* g = enforceEx!WriteException(fopen("some/other/file", "w"));
   // g is not null from here on

   Exception e = collectException(write(g, readln(f)));
   if (e)
   {
       ... an exception occurred...
       ... We have the exception to play around with...
   }

   string msg = collectExceptionMsg(write(g, readln(f)));
   if (msg)
   {
       ... an exception occurred...
       ... We have the message from the exception but not the exception...
   }

   char[] line;
   enforce(readln(f, line));
   return assumeUnique(line);
}
--------------------

    Macros:
        WIKI = Phobos/StdException

    Copyright: Copyright Andrei Alexandrescu 2008-, Jonathan M Davis 2011-.
    License:   $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
    Authors:   $(WEB erdani.org, Andrei Alexandrescu) and Jonathan M Davis
    Source:    $(PHOBOSSRC std/_exception.d)

 +/
module std.exception;

import std.array, std.c.string, std.conv, std.range, std.string, std.traits;
import core.exception, core.stdc.errno;

/++
    Asserts that the given expression does $(I not) throw the given type
    of $(D Throwable). If a $(D Throwable) of the given type is thrown,
    it is caught and does not escape assertNotThrown. Rather, an
    $(D AssertError) is thrown. However, any other $(D Throwable)s will escape.

    Params:
        T          = The $(D Throwable) to test for.
        expression = The expression to test.
        msg        = Optional message to output on test failure.
                     If msg is empty, and the thrown exception has a
                     non-empty msg field, the exception's msg field
                     will be output on test failure.

    Throws:
        $(D AssertError) if the given $(D Throwable) is thrown.

    Examples:
--------------------
assertNotThrown!StringException(enforceEx!StringException(true, "Error!"));

//Exception is the default.
assertNotThrown(enforceEx!StringException(true, "Error!"));

assert(collectExceptionMsg!AssertError(assertNotThrown!StringException(
           enforceEx!StringException(false, "Error!"))) ==
       `assertNotThrown failed: StringException was thrown: Error!`);
--------------------
  +/
void assertNotThrown(T : Throwable = Exception, E)
                    (lazy E expression,
                     string msg = null,
                     string file = __FILE__,
                     size_t line = __LINE__)
{
    try
        expression();
    catch(T t)
    {
        immutable message = msg.empty ? t.msg : msg;
        immutable tail = message.empty ? "." : ": " ~ message;
        throw new AssertError(format("assertNotThrown failed: %s was thrown%s",
                                     T.stringof,
                                     tail),
                              file,
                              line,
                              t);
    }
}

//Verify Examples
unittest
{
    assertNotThrown!StringException(enforceEx!StringException(true, "Error!"));

    //Exception is the default.
    assertNotThrown(enforceEx!StringException(true, "Error!"));

    assert(collectExceptionMsg!AssertError(assertNotThrown!StringException(
               enforceEx!StringException(false, "Error!"))) ==
           `assertNotThrown failed: StringException was thrown: Error!`);

    assert(collectExceptionMsg!AssertError(assertNotThrown!StringException(
               enforceEx!StringException(false, ""), "Error!")) ==
           `assertNotThrown failed: StringException was thrown: Error!`);

    assert(collectExceptionMsg!AssertError(assertNotThrown!StringException(
               enforceEx!StringException(false, ""))) ==
           `assertNotThrown failed: StringException was thrown.`);

    assert(collectExceptionMsg!AssertError(assertNotThrown!StringException(
               enforceEx!StringException(false, ""), "")) ==
           `assertNotThrown failed: StringException was thrown.`);
}

unittest
{
    void throwEx(Throwable t) { throw t; }
    void nothrowEx() { }

    try
        assertNotThrown!Exception(nothrowEx());
    catch(AssertError)
        assert(0);

    try
        assertNotThrown!Exception(nothrowEx(), "It's a message");
    catch(AssertError)
        assert(0);

    try
        assertNotThrown!AssertError(nothrowEx());
    catch(AssertError)
        assert(0);

    try
        assertNotThrown!AssertError(nothrowEx(), "It's a message");
    catch(AssertError)
        assert(0);

    {
        bool thrown = false;
        try
        {
            assertNotThrown!Exception(
                throwEx(new Exception("It's an Exception")));
        }
        catch(AssertError)
            thrown = true;

        assert(thrown);
    }

    {
        bool thrown = false;
        try
        {
            assertNotThrown!Exception(
                throwEx(new Exception("It's an Exception")), "It's a message");
        }
        catch(AssertError)
            thrown = true;

        assert(thrown);
    }

    {
        bool thrown = false;
        try
        {
            assertNotThrown!AssertError(
                throwEx(new AssertError("It's an AssertError",
                                        __FILE__,
                                        __LINE__)));
        }
        catch(AssertError)
            thrown = true;

        assert(thrown);
    }

    {
        bool thrown = false;
        try
        {
            assertNotThrown!AssertError(
                throwEx(new AssertError("It's an AssertError",
                                        __FILE__,
                                        __LINE__)),
                        "It's a message");
        }
        catch(AssertError)
            thrown = true;

        assert(thrown);
    }
}

/++
    Asserts that the given expression throws the given type of $(D Throwable).
    The $(D Throwable) is caught and does not escape assertThrown. However,
    any other $(D Throwable)s $(I will) escape, and if no $(D Throwable)
    of the given type is thrown, then an $(D AssertError) is thrown.

    Params:
        T          = The $(D Throwable) to test for.
        expression = The expression to test.
        msg        = Optional message to output on test failure.

    Throws:
        $(D AssertError) if the given $(D Throwable) is not thrown.

    Examples:
--------------------
assertThrown!StringException(enforceEx!StringException(false, "Error!"));

//Exception is the default.
assertThrown(enforceEx!StringException(false, "Error!"));

assert(collectExceptionMsg!AssertError(assertThrown!StringException(
           enforceEx!StringException(true, "Error!"))) ==
       `assertThrown failed: No StringException was thrown.`);
--------------------
  +/
void assertThrown(T : Throwable = Exception, E)
                 (lazy E expression,
                  string msg = null,
                  string file = __FILE__,
                  size_t line = __LINE__)
{
    bool thrown = false;

    try
        expression();
    catch(T t)
        thrown = true;

    if(!thrown)
    {
        immutable tail = msg.empty ? "." : ": " ~ msg;

        throw new AssertError(format("assertThrown failed: No %s was thrown%s",
                                     T.stringof,
                                     tail),
                              file,
                              line);
    }
}

//Verify Examples
unittest
{
    assertThrown!StringException(enforceEx!StringException(false, "Error!"));

    //Exception is the default.
    assertThrown(enforceEx!StringException(false, "Error!"));

    assert(collectExceptionMsg!AssertError(assertThrown!StringException(
               enforceEx!StringException(true, "Error!"))) ==
           `assertThrown failed: No StringException was thrown.`);
}

unittest
{
    void throwEx(Throwable t) { throw t; }
    void nothrowEx() { }

    try
        assertThrown!Exception(throwEx(new Exception("It's an Exception")));
    catch(AssertError)
        assert(0);

    try
    {
        assertThrown!Exception(throwEx(new Exception("It's an Exception")),
                               "It's a message");
    }
    catch(AssertError)
        assert(0);

    try
    {
        assertThrown!AssertError(throwEx(new AssertError("It's an AssertError",
                                                         __FILE__,
                                                         __LINE__)));
    }
    catch(AssertError)
        assert(0);

    try
    {
        assertThrown!AssertError(throwEx(new AssertError("It's an AssertError",
                                                         __FILE__,
                                                         __LINE__)),
                                 "It's a message");
    }
    catch(AssertError)
        assert(0);


    {
        bool thrown = false;
        try
            assertThrown!Exception(nothrowEx());
        catch(AssertError)
            thrown = true;

        assert(thrown);
    }

    {
        bool thrown = false;
        try
            assertThrown!Exception(nothrowEx(), "It's a message");
        catch(AssertError)
            thrown = true;

        assert(thrown);
    }

    {
        bool thrown = false;
        try
            assertThrown!AssertError(nothrowEx());
        catch(AssertError)
            thrown = true;

        assert(thrown);
    }

    {
        bool thrown = false;
        try
            assertThrown!AssertError(nothrowEx(), "It's a message");
        catch(AssertError)
            thrown = true;

        assert(thrown);
    }
}


/++
    If $(D !!value) is true, $(D value) is returned. Otherwise,
    $(D new Exception(msg)) is thrown.

    Note:
        $(D enforce) is used to throw exceptions and is therefore intended to
        aid in error handling. It is $(I not) intended for verifying the logic
        of your program. That is what $(D assert) is for. Also, do not use
        $(D enforce) inside of contracts (i.e. inside of $(D in) and $(D out)
        blocks and $(D invariant)s), because they will be compiled out when
        compiling with $(I -release). Use $(D assert) in contracts.

   Example:
--------------------
auto f = enforce(fopen("data.txt"));
auto line = readln(f);
enforce(line.length, "Expected a non-empty line.");
--------------------
 +/
T enforce(T)(T value, lazy const(char)[] msg = null, string file = __FILE__, size_t line = __LINE__)
{
    if (!value) bailOut(file, line, msg);
    return value;
}

/++
   $(RED Scheduled for deprecation in January 2013. If passing the file or line
         number explicitly, please use the version of enforce which takes them as
         function arguments. Taking them as template arguments causes
         unnecessary template bloat.)
 +/
T enforce(T, string file, size_t line = __LINE__)
    (T value, lazy const(char)[] msg = null)
{
    if (!value) bailOut(file, line, msg);
    return value;
}

/++
    If $(D !!value) is true, $(D value) is returned. Otherwise, the given
    delegate is called.

    The whole safety and purity are inferred from $(D Dg)'s safety and purity.
 +/
T enforce(T, Dg, string file = __FILE__, size_t line = __LINE__)
    (T value, scope Dg dg)
    if (is(Dg : void delegate()) || is(Dg : void function()))
{
    if (!value) dg();
    return value;
}

private void bailOut(string file, size_t line, in char[] msg) @safe pure
{
    throw new Exception(msg ? msg.idup : "Enforcement failed", file, line);
}

unittest
{
    assert (enforce(123) == 123);

    try
    {
        enforce(false, "error");
        assert (false);
    }
    catch (Exception e)
    {
        assert (e.msg == "error");
        assert (e.file == __FILE__);
        assert (e.line == __LINE__-7);
    }
}

// purity and safety inference test
unittest
{
    import std.typetuple;

    foreach (EncloseSafe; StaticTuple!(false, true))
    foreach (EnclosePure; StaticTuple!(false, true))
    {
        foreach (BodySafe; StaticTuple!(false, true))
        foreach (BodyPure; StaticTuple!(false, true))
        {
            enum code =
                "delegate void() " ~
                (EncloseSafe ? "@safe " : "") ~
                (EnclosePure ? "pure " : "") ~
                "{ ""enforce(true, { "
                        "int n; " ~
                        (BodySafe ? "" : "auto p = &n + 10; "    ) ~    // unsafe code
                        (BodyPure ? "" : "static int g; g = 10; ") ~    // impure code
                    "}); "
                "}";
            enum expect =
                (BodySafe || !EncloseSafe) && (!EnclosePure || BodyPure);

            version(none)
            pragma(msg, "safe = ", EncloseSafe?1:0, "/", BodySafe?1:0, ", ",
                        "pure = ", EnclosePure?1:0, "/", BodyPure?1:0, ", ",
                        "expect = ", expect?"OK":"NG", ", ",
                        "code = ", code);

            static assert(__traits(compiles, mixin(code)()) == expect);
        }
    }
}

// Test for bugzilla 8637
unittest
{
    struct S
    {
        static int g;
        ~this() {}  // impure & unsafe destructor
        bool opCast(T:bool)() {
            int* p = cast(int*)0;   // unsafe operation
            int n = g;              // impure operation
            return true;
        }
    }
    S s;

    enforce(s);
    enforce!(S, __FILE__, __LINE__)(s, ""); // scheduled for deprecation
    enforce(s, {});
    enforce(s, new Exception(""));

    errnoEnforce(s);

    alias Exception E1;
    static class E2 : Exception
    {
        this(string fn, size_t ln) { super("", fn, ln); }
    }
    static class E3 : Exception
    {
        this(string msg) { super(msg, __FILE__, __LINE__); }
    }
    enforceEx!E1(s);
    enforceEx!E2(s);
    enforceEx!E3(s, "");    // deprecated
}

/++
    If $(D !!value) is true, $(D value) is returned. Otherwise, $(D ex) is thrown.

   Example:
--------------------
auto f = enforce(fopen("data.txt"));
auto line = readln(f);
enforce(line.length, new IOException); // expect a non-empty line
--------------------
 +/
T enforce(T)(T value, lazy Throwable ex)
{
    if (!value) throw ex();
    return value;
}

unittest
{
    assertNotThrown(enforce(true, new Exception("this should not be thrown")));
    assertThrown(enforce(false, new Exception("this should be thrown")));
}

/++
    If $(D !!value) is true, $(D value) is returned. Otherwise,
    $(D new ErrnoException(msg)) is thrown. $(D ErrnoException) assumes that the
    last operation set $(D errno) to an error code.

   Example:
--------------------
auto f = errnoEnforce(fopen("data.txt"));
auto line = readln(f);
enforce(line.length); // expect a non-empty line
--------------------
 +/
T errnoEnforce(T, string file = __FILE__, size_t line = __LINE__)
    (T value, lazy string msg = null)
{
    if (!value) throw new ErrnoException(msg, file, line);
    return value;
}


/++
    If $(D !!value) is $(D true), $(D value) is returned. Otherwise,
    $(D new E(msg, file, line)) is thrown. Or if $(D E) doesn't take a message
    and can be constructed with $(D new E(file, line)), then
    $(D new E(file, line)) will be thrown.

   Example:
--------------------
 auto f = enforceEx!FileMissingException(fopen("data.txt"));
 auto line = readln(f);
 enforceEx!DataCorruptionException(line.length);
--------------------
 +/
template enforceEx(E)
    if (is(typeof(new E("", __FILE__, __LINE__))))
{
    T enforceEx(T)(T value, lazy string msg = "", string file = __FILE__, size_t line = __LINE__)
    {
        if (!value) throw new E(msg, file, line);
        return value;
    }
}

template enforceEx(E)
    if (is(typeof(new E(__FILE__, __LINE__))) && !is(typeof(new E("", __FILE__, __LINE__))))
{
    T enforceEx(T)(T value, string file = __FILE__, size_t line = __LINE__)
    {
        if (!value) throw new E(file, line);
        return value;
    }
}

// Explicitly undocumented. It will be removed in November 2013.
deprecated("Please use the version of enforceEx which takes an exception that constructs with new E(msg, file, line).")
template enforceEx(E)
    if (is(typeof(new E(""))) && !is(typeof(new E("", __FILE__, __LINE__))) && !is(typeof(new E(__FILE__, __LINE__))))
{
    T enforceEx(T)(T value, lazy string msg = "")
    {
        if (!value) throw new E(msg);
        return value;
    }
}

unittest
{
    assertNotThrown(enforceEx!Exception(true));
    assertNotThrown(enforceEx!Exception(true, "blah"));
    assertNotThrown(enforceEx!OutOfMemoryError(true));

    {
        auto e = collectException(enforceEx!Exception(false));
        assert(e !is null);
        assert(e.msg.empty);
        assert(e.file == __FILE__);
        assert(e.line == __LINE__ - 4);
    }

    {
        auto e = collectException(enforceEx!Exception(false, "hello", "file", 42));
        assert(e !is null);
        assert(e.msg == "hello");
        assert(e.file == "file");
        assert(e.line == 42);
    }
}

unittest
{
    alias enforceEx!Exception enf;
    assertNotThrown(enf(true));
    assertThrown(enf(false, "blah"));
}


/++
    Catches and returns the exception thrown from the given expression.
    If no exception is thrown, then null is returned and $(D result) is
    set to the result of the expression.

    Note that while $(D collectException) $(I can) be used to collect any
    $(D Throwable) and not just $(D Exception)s, it is generally ill-advised to
    catch anything that is neither an $(D Exception) nor a type derived from
    $(D Exception). So, do not use $(D collectException) to collect
    non-$(D Exception)s unless you're sure that that's what you really want to
    do.

    Params:
        T          = The type of exception to catch.
        expression = The expression which may throw an exception.
        result     = The result of the expression if no exception is thrown.

    Example:
--------------------
int[] a = new int[3];
int b;
assert(collectException(a[4], b));
--------------------
+/
T collectException(T = Exception, E)(lazy E expression, ref E result)
{
    try
    {
        result = expression();
    }
    catch (T e)
    {
        return e;
    }
    return null;
}

unittest
{
    int[] a = new int[3];
    int b;
    int foo() { throw new Exception("blah"); }
    assert(collectException(foo(), b));
}

/++
    Catches and returns the exception thrown from the given expression.
    If no exception is thrown, then null is returned. $(D E) can be
    $(D void).

    Note that while $(D collectException) $(I can) be used to collect any
    $(D Throwable) and not just $(D Exception)s, it is generally ill-advised to
    catch anything that is neither an $(D Exception) nor a type derived from
    $(D Exception). So, do not use $(D collectException) to collect
    non-$(D Exception)s unless you're sure that that's what you really want to
    do.

    Params:
        T          = The type of exception to catch.
        expression = The expression which may throw an exception.
+/
T collectException(T : Throwable = Exception, E)(lazy E expression)
{
    try
    {
        expression();
    }
    catch (T t)
    {
        return t;
    }
    return null;
}

unittest
{
    int foo() { throw new Exception("blah"); }
    assert(collectException(foo()));
}

/++
    Catches the exception thrown from the given expression and returns the
    msg property of that exception. If no exception is thrown, then null is
    returned. $(D E) can be $(D void).

    If an exception is thrown but it has an empty message, then
    $(D emptyExceptionMsg) is returned.

    Note that while $(D collectExceptionMsg) $(I can) be used to collect any
    $(D Throwable) and not just $(D Exception)s, it is generally ill-advised to
    catch anything that is neither an $(D Exception) nor a type derived from
    $(D Exception). So, do not use $(D collectExceptionMsg) to collect
    non-$(D Exception)s unless you're sure that that's what you really want to
    do.

    Params:
        T          = The type of exception to catch.
        expression = The expression which may throw an exception.

    Examples:
--------------------
void throwFunc() {throw new Exception("My Message.");}
assert(collectExceptionMsg(throwFunc()) == "My Message.");

void nothrowFunc() {}
assert(collectExceptionMsg(nothrowFunc()) is null);

void throwEmptyFunc() {throw new Exception("");}
assert(collectExceptionMsg(throwEmptyFunc()) == emptyExceptionMsg);
--------------------
+/
string collectExceptionMsg(T = Exception, E)(lazy E expression)
{
    try
    {
        expression();

        return cast(string)null;
    }
    catch(T e)
        return e.msg.empty ? emptyExceptionMsg : e.msg;
}

//Verify Examples.
unittest
{
    void throwFunc() {throw new Exception("My Message.");}
    assert(collectExceptionMsg(throwFunc()) == "My Message.");

    void nothrowFunc() {}
    assert(collectExceptionMsg(nothrowFunc()) is null);

    void throwEmptyFunc() {throw new Exception("");}
    assert(collectExceptionMsg(throwEmptyFunc()) == emptyExceptionMsg);
}

/++
    Value that collectExceptionMsg returns when it catches an exception
    with an empty exception message.
 +/
enum emptyExceptionMsg = "<Empty Exception Message>";

/**
 * Casts a mutable array to an immutable array in an idiomatic
 * manner. Technically, $(D assumeUnique) just inserts a cast,
 * but its name documents assumptions on the part of the
 * caller. $(D assumeUnique(arr)) should only be called when
 * there are no more active mutable aliases to elements of $(D
 * arr). To strenghten this assumption, $(D assumeUnique(arr))
 * also clears $(D arr) before returning. Essentially $(D
 * assumeUnique(arr)) indicates commitment from the caller that there
 * is no more mutable access to any of $(D arr)'s elements
 * (transitively), and that all future accesses will be done through
 * the immutable array returned by $(D assumeUnique).
 *
 * Typically, $(D assumeUnique) is used to return arrays from
 * functions that have allocated and built them.
 *
 * Example:
 *
 * ----
 * string letters()
 * {
 *   char[] result = new char['z' - 'a' + 1];
 *   foreach (i, ref e; result)
 *   {
 *     e = 'a' + i;
 *   }
 *   return assumeUnique(result);
 * }
 * ----
 *
 * The use in the example above is correct because $(D result)
 * was private to $(D letters) and is unaccessible in writing
 * after the function returns. The following example shows an
 * incorrect use of $(D assumeUnique).
 *
 * Bad:
 *
 * ----
 * private char[] buffer;
 * string letters(char first, char last)
 * {
 *   if (first >= last) return null; // fine
 *   auto sneaky = buffer;
 *   sneaky.length = last - first + 1;
 *   foreach (i, ref e; sneaky)
 *   {
 *     e = 'a' + i;
 *   }
 *   return assumeUnique(sneaky); // BAD
 * }
 * ----
 *
 * The example above wreaks havoc on client code because it is
 * modifying arrays that callers considered immutable. To obtain an
 * immutable array from the writable array $(D buffer), replace
 * the last line with:
 * ----
 * return to!(string)(sneaky); // not that sneaky anymore
 * ----
 *
 * The call will duplicate the array appropriately.
 *
 * Checking for uniqueness during compilation is possible in certain
 * cases (see the $(D unique) and $(D lent) keywords in
 * the $(WEB archjava.fluid.cs.cmu.edu/papers/oopsla02.pdf, ArchJava)
 * language), but complicates the language considerably. The downside
 * of $(D assumeUnique)'s convention-based usage is that at this
 * time there is no formal checking of the correctness of the
 * assumption; on the upside, the idiomatic use of $(D
 * assumeUnique) is simple and rare enough to be tolerable.
 *
 */
immutable(T)[] assumeUnique(T)(T[] array) pure nothrow
{
    return .assumeUnique(array);    // call ref version
}
/// ditto
immutable(T)[] assumeUnique(T)(ref T[] array) pure nothrow
{
    auto result = cast(immutable(T)[]) array;
    array = null;
    return result;
}

unittest
{
    int[] arr = new int[1];
    auto arr1 = assumeUnique(arr);
    assert(is(typeof(arr1) == immutable(int)[]) && arr == null);
}

immutable(T[U]) assumeUnique(T, U)(ref T[U] array) pure nothrow
{
    auto result = cast(immutable(T[U])) array;
    array = null;
    return result;
}

// @@@BUG@@@
version(none) unittest
{
    int[string] arr = ["a":1];
    auto arr1 = assumeUnique(arr);
    assert(is(typeof(arr1) == immutable(int[string])) && arr == null);
}

/**
Returns $(D true) if $(D source)'s representation embeds a pointer
that points to $(D target)'s representation or somewhere inside
it.

Note that evaluating $(D pointsTo(x, x)) checks whether $(D x) has
internal pointers. This should only be done as an assertive test,
as the language is free to assume objects don't have internal pointers
(TDPL 7.1.3.5).
*/
bool pointsTo(S, T, Tdummy=void)(auto ref const S source, auto ref const T target) @trusted pure nothrow
    if ((__traits(isRef, source) || isDynamicArray!S) &&    // lvalue or slice rvalue
        (__traits(isRef, target) || isDynamicArray!T))      // lvalue or slice rvalue
{
    static if (is(S P : U*, U))
    {
        const m = cast(void*) source,
              b = cast(void*) &target, e = b + target.sizeof;
        return b <= m && m < e;
    }
    else static if (is(S == struct))
    {
        foreach (i, Subobj; typeof(source.tupleof))
            if (pointsTo(source.tupleof[i], target)) return true;
        return false;
    }
    else static if (isStaticArray!S)
    {
        foreach (size_t i; 0 .. S.length)
            if (pointsTo(source[i], target)) return true;
        return false;
    }
    else static if (isDynamicArray!S)
    {
        return overlap(cast(void[])source, cast(void[])(&target)[0 .. 1]).length != 0;
    }
    else
    {
        return false;
    }
}
// for shared objects
bool pointsTo(S, T)(ref const shared S source, ref const shared T target) @trusted pure nothrow
{
    return pointsTo!(shared S, shared T, void)(source, target);
}
unittest
{
    struct S1 { int a; S1 * b; }
    S1 a1;
    S1 * p = &a1;
    assert(pointsTo(p, a1));

    S1 a2;
    a2.b = &a1;
    assert(pointsTo(a2, a1));

    struct S3 { int[10] a; }
    S3 a3;
    auto a4 = a3.a[2 .. 3];
    assert(pointsTo(a4, a3));

    auto a5 = new double[4];
    auto a6 = a5[1 .. 2];
    assert(!pointsTo(a5, a6));

    auto a7 = new double[3];
    auto a8 = new double[][1];
    a8[0] = a7;
    assert(!pointsTo(a8[0], a8[0]));

    // don't invoke postblit on subobjects
    {
        static struct NoCopy { this(this) { assert(0); } }
        static struct Holder { NoCopy a, b, c; }
        Holder h;
        pointsTo(h, h);
    }

    shared S3 sh3;
    shared sh3sub = sh3.a[];
    assert(pointsTo(sh3sub, sh3));

    int[] darr = [1, 2, 3, 4];

    //dynamic arrays don't point to each other, or slices of themselves
    assert(!pointsTo(darr, darr));
    assert(!pointsTo(darr, darr[0 .. 1]));
    assert(!pointsTo(darr[0 .. 1], darr));

    //But they do point their elements
    foreach(i; 0 .. 4)
        assert(pointsTo(darr, darr[i]));
    assert(pointsTo(darr[0..3], darr[2]));
    assert(!pointsTo(darr[0..3], darr[3]));
}

unittest
{
    //tests with static arrays
    //Static arrays themselves are just objects, and don't really *point* to anything.
    //They aggregate their contents, much the same way a structure aggregates its attributes.
    //*However* The elements inside the static array may themselves point to stuff.

    //Standard array
    int[2] k;
    assert(!pointsTo(k, k)); //an array doesn't point to itself
    //Technically, k doesn't point its elements, although it does alias them
    assert(!pointsTo(k, k[0]));
    assert(!pointsTo(k, k[1]));
    //But an extracted slice will point to the same array.
    assert(pointsTo(k[], k));
    assert(pointsTo(k[], k[1]));

    //An array of pointers
    int*[2] pp;
    int a;
    int b;
    pp[0] = &a;
    assert( pointsTo(pp, a));  //The array contains a pointer to a
    assert(!pointsTo(pp, b));  //The array does NOT contain a pointer to b
    assert(!pointsTo(pp, pp)); //The array does not point itslef

    //A struct containing a static array of pointers
    static struct S
    {
        int*[2] p;
    }
    S s;
    s.p[0] = &a;
    assert( pointsTo(s, a)); //The struct contains an array that points a
    assert(!pointsTo(s, b)); //But doesn't point b
    assert(!pointsTo(s, s)); //The struct doesn't actually point itslef.

    //An array containing structs that have pointers
    static struct SS
    {
        int* p;
    }
    SS[2] ss = [SS(&a), SS(null)];
    assert( pointsTo(ss, a));  //The array contains a struct that points to a
    assert(!pointsTo(ss, b));  //The array doesn't contains a struct that points to b
    assert(!pointsTo(ss, ss)); //The array doesn't point itself.
}

/*********************
 * Thrown if errors that set $(D errno) occur.
 */
class ErrnoException : Exception
{
    uint errno;                 // operating system error code
    this(string msg, string file = null, size_t line = 0)
    {
        errno = .errno;
        version (linux)
        {
            char[1024] buf = void;
            auto s = std.c.string.strerror_r(errno, buf.ptr, buf.length);
        }
        else
        {
            auto s = std.c.string.strerror(errno);
        }
        super(msg~" ("~to!string(s)~")", file, line);
    }
}

// structuralCast
// class-to-class structural cast
Target structuralCast(Target, Source)(Source obj)
    if (is(Source == class) || is(Target == class))
{
    // For the structural cast to work, the source and the target must
    // have the same base class, and the target must add no data or
    // methods
    static assert(0, "Not implemented");
}

// interface-to-interface structural cast
Target structuralCast(Target, Source)(Source obj)
    if (is(Source == interface) || is(Target == interface))
{
}

unittest
{
    interface I1 { void f1(); }
    interface I2 { void f2(); }
    interface I12 : I1, I2 { }
    //pragma(msg, TransitiveBaseTypeTuple!I12.stringof);
    //static assert(is(TransitiveBaseTypeTuple!I12 == TypeTuple!(I2, I1)));
}

// Target structuralCast(Target, Source)(Source obj)
//     if (is(Source == interface) || is(Target == interface))
// {
//     static assert(is(BaseTypeTuple!(Source)[0] ==
//                     BaseTypeTuple!(Target)[0]));
//     alias BaseTypeTuple!(Source)[1 .. $] SBases;
//     alias BaseTypeTuple!(Target)[1 .. $] TBases;
//         else
//         {
//             // interface-to-class
//             static assert(0);
//         }
//     }
//     else
//     {
//         static if (is(Source == class))
//         {
//             // class-to-interface structural cast
//             alias BaseTypeTuple!(Source)[1 .. $] SBases;
//             alias BaseTypeTuple!(Target) TBases;
//         }
//         else
//         {
//             // interface-to-interface structural cast
//             alias BaseTypeTuple!(Source) SBases;
//             alias BaseTypeTuple!(Target) TBases;
//         }
//     }
//     static assert(SBases.length >= TBases.length,
//             "Cannot structurally cast to a target with"
//             " more interfaces implemented");
//     static assert(
//         is(typeof(Target.tupleof) == typeof(Source.tupleof)),
//             "Cannot structurally cast to a target with more fields");
//     // Target bases must be a prefix of the source bases
//     foreach (i, B; TBases)
//     {
//         static assert(is(SBases[i] == B)
//                 || is(SBases[i] == interface) && is(SBases[i] : B),
//                 SBases[i].stringof ~ " does not inherit "
//                 ~ B.stringof);
//     }
//     union Result
//     {
//         Source src;
//         Target tgt;
//     }
//     Result result = { obj };
//     return result.tgt;
// }

template structurallyCompatible(S, T) if (!isArray!S || !isArray!T)
{
    enum structurallyCompatible =
        FieldTypeTuple!S.length >= FieldTypeTuple!T.length
        && is(FieldTypeTuple!S[0 .. FieldTypeTuple!T.length]
                == FieldTypeTuple!T);
}

template structurallyCompatible(S, T) if (isArray!S && isArray!T)
{
    enum structurallyCompatible =
        .structurallyCompatible!(ElementType!S, ElementType!T) &&
        .structurallyCompatible!(ElementType!T, ElementType!S);
}

unittest
{
    // struct X { uint a; }
    // static assert(structurallyCompatible!(uint[], X[]));
    // struct Y { uint a, b; }
    // static assert(!structurallyCompatible!(uint[], Y[]));
    // static assert(!structurallyCompatible!(Y[], uint[]));
    // static assert(!structurallyCompatible!(Y[], X[]));
}

/*
Structural cast. Allows casting among class types that logically have
a common base, but that base is not made explicit.

Example:
----
interface Document { ... }
interface Storable { ... }
interface StorableDocument : Storable, Document { ... }
class Doc : Storable, Document { ... }
void process(StorableDocument d);
...

auto c = new Doc;
process(c); // does not work
process(structuralCast!StorableDocument(c)); // works
 */

// template structuralCast(Target)
// {
//     Target structuralCast(Source)(Source obj)
//     {
//         static if (is(Source : Object) || is(Source == interface))
//         {
//             return .structuralCastImpl!(Target)(obj);
//         }
//         else
//         {
//             static if (structurallyCompatible!(Source, Target))
//                 return *(cast(Target*) &obj);
//             else
//                 static assert(false);
//         }
//     }
// }

unittest
{
    // interface I1 {}
    // interface I2 {}
    // class Base : I1 { int x; }
    // class A : I1 {}
    // class B : I1, I2 {}

    // auto b = new B;
    // auto a = structuralCast!(A)(b);
    // assert(a);

    // struct X { int a; }
    // int[] arr = [ 1 ];
    // auto x = structuralCast!(X[])(arr);
    // assert(x[0].a == 1);
}

unittest
{
    // interface Document { int fun(); }
    // interface Storable { int gun(); }
    // interface StorableDocument : Storable, Document {  }
    // class Doc : Storable, Document {
    //     int fun() { return 42; }
    //     int gun() { return 43; }
    // }
    // void process(StorableDocument d) {
    //     assert(d.fun + d.gun == 85, text(d.fun + d.gun));
    // }

    // auto c = new Doc;
    // Document d = c;
    // //process(c); // does not work
    // union A
    // {
    //     Storable s;
    //     StorableDocument sd;
    // }
    // A a = { c };
    //process(a.sd); // works
    //process(structuralCast!StorableDocument(d)); // works
}

/++
    ML-style functional exception handling. Runs the supplied expression and
    returns its result. If the expression throws a $(D Throwable), runs the
    supplied error handler instead and return its result. The error handler's
    type must be the same as the expression's type.

    Params:
        E            = The type of $(D Throwable)s to catch. Defaults to ${D Exception}
        T            = The return type of the expression and the error handler.
        expression   = The expression to run and return its result.
        errorHandler = The handler to run if the expression throwed.

    Examples:
--------------------
    //Revert to a default value upon an error:
    assert("x".to!int().ifThrown(0) == 0);
--------------------

    You can also chain multiple calls to ifThrown, each capturing errors from the
    entire preceding expression.

    Example:
--------------------
    //Chaining multiple calls to ifThrown to attempt multiple things in a row:
    string s="true";
    assert(s.to!int().
            ifThrown(cast(int)s.to!double()).
            ifThrown(cast(int)s.to!bool())
            == 1);

    //Respond differently to different types of errors
    assert(enforce("x".to!int() < 1).to!string()
            .ifThrown!ConvException("not a number")
            .ifThrown!Exception("number too small")
            == "not a number");
--------------------

    The expression and the errorHandler must have a common type they can both
    be implicitly casted to, and that type will be the type of the compound
    expression.

    Examples:
--------------------
    //null and new Object have a common type(Object).
    static assert(is(typeof(null.ifThrown(new Object())) == Object));
    static assert(is(typeof((new Object()).ifThrown(null)) == Object));

    //1 and new Object do not have a common type.
    static assert(!__traits(compiles, 1.ifThrown(new Object())));
    static assert(!__traits(compiles, (new Object()).ifThrown(1)));
--------------------

    If you need to use the actual thrown expection, you can use a delegate.
    Example:
--------------------
    //Use a lambda to get the thrown object.
    assert("%s".format().ifThrown!Exception(e => e.classinfo.name) == "std.format.FormatException");
--------------------
    +/
//lazy version
CommonType!(T1, T2) ifThrown(E : Throwable = Exception, T1, T2)(lazy scope T1 expression, lazy scope T2 errorHandler)
{
    static assert(!is(typeof(return) == void),
            "The error handler's return value("~T2.stringof~") does not have a common type with the expression("~T1.stringof~").");
    try
    {
        return expression();
    }
    catch(E)
    {
        return errorHandler();
    }
}

///ditto
//delegate version
CommonType!(T1, T2) ifThrown(E : Throwable, T1, T2)(lazy scope T1 expression, scope T2 delegate(E) errorHandler)
{
    static assert(!is(typeof(return) == void),
            "The error handler's return value("~T2.stringof~") does not have a common type with the expression("~T1.stringof~").");
    try
    {
        return expression();
    }
    catch(E e)
    {
        return errorHandler(e);
    }
}

///ditto
//delegate version, general overload to catch any Exception
CommonType!(T1, T2) ifThrown(T1, T2)(lazy scope T1 expression, scope T2 delegate(Exception) errorHandler)
{
    static assert(!is(typeof(return) == void),
            "The error handler's return value("~T2.stringof~") does not have a common type with the expression("~T1.stringof~").");
    try
    {
        return expression();
    }
    catch(Exception e)
    {
        return errorHandler(e);
    }
}

//Verify Examples
unittest
{
    //Revert to a default value upon an error:
    assert("x".to!int().ifThrown(0) == 0);

    //Chaining multiple calls to ifThrown to attempt multiple things in a row:
    string s="true";
    assert(s.to!int().
            ifThrown(cast(int)s.to!double()).
            ifThrown(cast(int)s.to!bool())
            == 1);

    //Respond differently to different types of errors
    assert(enforce("x".to!int() < 1).to!string()
            .ifThrown!ConvException("not a number")
            .ifThrown!Exception("number too small")
            == "not a number");

    //null and new Object have a common type(Object).
    static assert(is(typeof(null.ifThrown(new Object())) == Object));
    static assert(is(typeof((new Object()).ifThrown(null)) == Object));

    //1 and new Object do not have a common type.
    static assert(!__traits(compiles, 1.ifThrown(new Object())));
    static assert(!__traits(compiles, (new Object()).ifThrown(1)));

    //Use a lambda to get the thrown object.
    assert("%s".format().ifThrown(e => e.classinfo.name) == "std.format.FormatException");
}

unittest
{
    //Basic behaviour - all versions.
    assert("1".to!int().ifThrown(0) == 1);
    assert("x".to!int().ifThrown(0) == 0);
    assert("1".to!int().ifThrown!ConvException(0) == 1);
    assert("x".to!int().ifThrown!ConvException(0) == 0);
    assert("1".to!int().ifThrown(e=>0) == 1);
    assert("x".to!int().ifThrown(e=>0) == 0);
    static if (__traits(compiles, 0.ifThrown!Exception(e => 0))) //This will only work with a fix that was not yet pulled
    {
        assert("1".to!int().ifThrown!ConvException(e=>0) == 1);
        assert("x".to!int().ifThrown!ConvException(e=>0) == 0);
    }

    //Exceptions other than stated not caught.
    assert("x".to!int().ifThrown!StringException(0).collectException!ConvException() !is null);
    static if (__traits(compiles, 0.ifThrown!Exception(e => 0))) //This will only work with a fix that was not yet pulled
    {
        assert("x".to!int().ifThrown!StringException(e=>0).collectException!ConvException() !is null);
    }

    //Default does not include errors.
    int[] a=[];
    assert(a[0].ifThrown(0).collectException!RangeError() !is null);
    assert(a[0].ifThrown(e=>0).collectException!RangeError() !is null);

    //Incompatible types are not accepted.
    static assert(!__traits(compiles, 1.ifThrown(new Object())));
    static assert(!__traits(compiles, (new Object()).ifThrown(1)));
    static assert(!__traits(compiles, 1.ifThrown(e=>new Object())));
    static assert(!__traits(compiles, (new Object()).ifThrown(e=>1)));
}
