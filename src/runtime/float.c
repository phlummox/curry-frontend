#line 13 "float.nw"
#include "config.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "debug.h"
#include "run.h"
#include "heap.h"
#include "stack.h"
#include "eval.h"
#include "threads.h"
#include "cam.h"
#include "trace.h"

#line 33 "float.nw"
DECLARE_ENTRYPOINT(___43__46_);
DECLARE_LABEL(___43__46__1);

FUNCTION(___43__46_)
{
    Node *aux;

    EXPORT_LABEL(___43__46_)
 ENTRY_LABEL(___43__46_)
    EVAL_RIGID_FLOAT(___43__46_);
    aux   = sp[0];
    sp[0] = sp[1];
    sp[1] = aux;
    GOTO(___43__46__1);
}

static
FUNCTION(___43__46__1)
{
    double d, e;
    Node   *r;

 ENTRY_LABEL(___43__46__1)
    EVAL_RIGID_FLOAT(___43__46__1);
    get_float_val(d, sp[1]->f);
    get_float_val(e, sp[0]->f);
    sp += 2;

    CHECK_HEAP(float_node_size);
    r	    = (Node *)hp;
    r->info = &float_info;
    put_float_val(r->f, d + e);
    hp += float_node_size;
    RETURN(r);
}


DECLARE_ENTRYPOINT(___45__46_);
DECLARE_LABEL(___45__46__1);

FUNCTION(___45__46_)
{
    Node *aux;

    EXPORT_LABEL(___45__46_)
 ENTRY_LABEL(___45__46_)
    EVAL_RIGID_FLOAT(___45__46_);
    aux   = sp[0];
    sp[0] = sp[1];
    sp[1] = aux;
    GOTO(___45__46__1);
}

static
FUNCTION(___45__46__1)
{
    double d, e;
    Node   *r;

 ENTRY_LABEL(___45__46__1)
    EVAL_RIGID_FLOAT(___45__46__1);
    get_float_val(d, sp[1]->f);
    get_float_val(e, sp[0]->f);
    sp += 2;

    CHECK_HEAP(float_node_size);
    r	    = (Node *)hp;
    r->info = &float_info;
    put_float_val(r->f, d - e);
    hp += float_node_size;
    RETURN(r);
}


DECLARE_ENTRYPOINT(___42__46_);
DECLARE_LABEL(___42__46__1);

FUNCTION(___42__46_)
{
    Node *aux;

    EXPORT_LABEL(___42__46_)
 ENTRY_LABEL(___42__46_)
    EVAL_RIGID_FLOAT(___42__46_);
    aux   = sp[0];
    sp[0] = sp[1];
    sp[1] = aux;
    GOTO(___42__46__1);
}

static
FUNCTION(___42__46__1)
{
    double d, e;
    Node   *r;

 ENTRY_LABEL(___42__46__1)
    EVAL_RIGID_FLOAT(___42__46__1);
    get_float_val(d, sp[1]->f);
    get_float_val(e, sp[0]->f);
    sp += 2;

    CHECK_HEAP(float_node_size);
    r	    = (Node *)hp;
    r->info = &float_info;
    put_float_val(r->f, d * e);
    hp += float_node_size;
    RETURN(r);
}

DECLARE_ENTRYPOINT(___47__46_);
DECLARE_LABEL(___47__46__1);

FUNCTION(___47__46_)
{
    Node *aux;

    EXPORT_LABEL(___47__46_)
 ENTRY_LABEL(___47__46_)
    EVAL_RIGID_FLOAT(___47__46_);
    aux   = sp[0];
    sp[0] = sp[1];
    sp[1] = aux;
    GOTO(___47__46__1);
}

static
FUNCTION(___47__46__1)
{
    double d, e;
    Node   *r;

 ENTRY_LABEL(___47__46__1)
    EVAL_RIGID_FLOAT(___47__46__1);
    get_float_val(d, sp[1]->f);
    get_float_val(e, sp[0]->f);
    sp += 2;

    CHECK_HEAP(float_node_size);
    r	    = (Node *)hp;
    r->info = &float_info;
    put_float_val(r->f, d / e);
    hp += float_node_size;
    RETURN(r);
}

#line 184 "float.nw"
DECLARE_ENTRYPOINT(__floatFromInt);

FUNCTION(__floatFromInt)
{
    long i;
    Node *r;

    EXPORT_LABEL(__floatFromInt)
 ENTRY_LABEL(__floatFromInt)
    EVAL_RIGID_INT(__floatFromInt);
    i	= int_val(sp[0]);
    sp += 1;

    CHECK_HEAP(float_node_size);
    r	    = (Node *)hp;
    r->info = &float_info;
    put_float_val(r->f, i);
    hp += float_node_size;
    RETURN(r);
}


DECLARE_ENTRYPOINT(__truncateFloat);

FUNCTION(__truncateFloat)
{
    double d;
    Node   *r;

    EXPORT_LABEL(__truncateFloat)
 ENTRY_LABEL(__truncateFloat)
    EVAL_RIGID_FLOAT(__truncateFloat);
    get_float_val(d, sp[0]->f);
    sp += 1;

#if ONLY_BOXED_OBJECTS
    CHECK_HEAP(int_node_size);
    r	    = (Node *)hp;
    r->info = &int_info;
    r->i.i  = (int)d;
    hp	   += int_node_size;
#else
    r = mk_int((int)d);
#endif
    RETURN(r);
}


DECLARE_ENTRYPOINT(__roundFloat);

FUNCTION(__roundFloat)
{
    double d, frac;
    Node   *r;

    EXPORT_LABEL(__roundFloat)
 ENTRY_LABEL(__roundFloat)
    EVAL_RIGID_FLOAT(__roundFloat);
    get_float_val(d, sp[0]->f);
    sp += 1;
#define odd(n) (n & 0x01)
    frac = modf(d, &d);
    if ( frac > 0.5 || (frac == 0.5 && odd((int)d)) )
	d += 1.0;
    else if ( frac < -0.5 || (frac == -0.5 && odd((int)d)) )
	d -= 1.0;
#undef odd

#if ONLY_BOXED_OBJECTS
    CHECK_HEAP(int_node_size);
    r	    = (Node *)hp;
    r->info = &int_info;
    r->i.i  = (int)d;
    hp	   += int_node_size;
#else
    r = mk_int((int)d);
#endif
    RETURN(r);
}
