/*********************************************************************
 *   Copyright 2018, UCAR/Unidata
 *   See netcdf/COPYRIGHT file for copying and redistribution conditions.
 *********************************************************************/

#include "includes.h"
#include <stddef.h>

#ifdef ENABLE_C

#include <math.h> 
#ifndef isnan
extern int isnan(double);
#endif

static int c_uid = 0;

static int
c_charconstant(Generator* generator, Symbol* sym, Bytebuffer* codebuf, ...)
{
    /* Escapes and quoting will be handled in genc_write */
    /* Just transfer charbuf to codebuf */
    Bytebuffer* charbuf;
    va_list ap;
    va_start(ap,codebuf);
    charbuf = va_arg(ap, Bytebuffer*);
    va_end(ap);
    bbNull(charbuf);
    bbCatbuf(codebuf,charbuf);
    return 1;
}

static int
c_constant(Generator* generator, Symbol* sym, NCConstant* con, Bytebuffer* buf,...)
{
    Bytebuffer* codetmp = bbNew();
    char* special = NULL;

    switch (con->nctype) {
    case NC_CHAR:
	if(con->value.charv == '\'') 
	    bbprintf(codetmp,"'\\''");
	else
	    bbprintf(codetmp,"'%s'",cescapifychar(con->value.charv,'\''));
	break;
    case NC_BYTE:
	bbprintf(codetmp,"%hhd",con->value.int8v);
	break;
    case NC_SHORT:
	bbprintf(codetmp,"%hd",con->value.int16v);
	break;
    case NC_INT:
	bbprintf(codetmp,"%d",con->value.int32v);
	break;
    case NC_FLOAT:
	/* Special case for nanf */
	if(isnan(con->value.floatv))
	    bbprintf(codetmp,"nanf");
	else
	    bbprintf(codetmp,"%f",con->value.floatv);
	break;
    case NC_DOUBLE:
	/* Special case for nan */
	if(isnan(con->value.doublev))
	    bbprintf(codetmp,"nan");
	else
	    bbprintf(codetmp,"%lf",con->value.doublev);
	break;
    case NC_UBYTE:
        bbprintf(codetmp,"%hhuU",con->value.uint8v);
	break;
    case NC_USHORT:
	bbprintf(codetmp,"%huU",con->value.uint16v);
	break;
    case NC_UINT:
	bbprintf(codetmp,"%uU",con->value.uint32v);
	break;
    case NC_INT64:
	bbprintf(codetmp,"%lldLL",con->value.int64v);
	break;
    case NC_UINT64:
	bbprintf(codetmp,"%lluULL",con->value.uint64v);
	break;
    case NC_ECONST:
	bbprintf(codetmp,"%s",cname(con->value.enumv));
	break;
    case NC_NIL:
    case NC_STRING: { /* handle separately */
	if(con->value.stringv.len == 0 && con->value.stringv.stringv == NULL) {
            bbprintf(codetmp,"NULL");
	} else {
	    char* escaped = escapify(con->value.stringv.stringv,
				 '"',con->value.stringv.len);
	    special = poolalloc(1+2+strlen(escaped));
	    strcpy(special,"\"");
	    strcat(special,escaped);
	    strcat(special,"\"");
	}
	} break;
    case NC_OPAQUE: {
	char* p;
	size_t bslen = (size_t)(4*con->value.opaquev.len);
	special = poolalloc(bslen+2+1);
	strcpy(special,"\"");
	p = con->value.opaquev.stringv;
	while(*p) {
	    strlcat(special,"\\x",bslen+3);
	    strlcat(special,p,bslen+3);
	    p += 2;	
	}
	strlcat(special,"\"",bslen+3);
	} break;

    default: PANIC1("ncstype: bad type code: %d",con->nctype);

    }
    if(special == NULL)
        bbCatbuf(buf,codetmp);
    else
	bbCat(buf,special);
    bbFree(codetmp);
    return 1;
}

static int
c_listbegin(Generator* generator, Symbol* sym, void* liststate, ListClass lc, size_t size, Bytebuffer* codebuf, int* uidp, ...)
{
    if(uidp) *uidp = ++c_uid;
    switch (lc) {
    case LISTVLEN:
    case LISTATTR:
    case LISTDATA:
	break;
    case LISTFIELDARRAY:
    case LISTCOMPOUND:
        bbAppend(codebuf,'{');
	break;
    }
    return 1;
}

static int
c_list(Generator* generator, Symbol* sym, void* liststate, ListClass lc, int uid, size_t count, Bytebuffer* codebuf, ...)
{
    switch (lc) {
    case LISTVLEN:
    case LISTATTR:
        if(count > 0) bbCat(codebuf,", ");
	break;
    case LISTDATA:
    case LISTCOMPOUND:
    case LISTFIELDARRAY:
        bbAppend(codebuf,' ');
	break;
    }
    return 1;
}

static int
c_listend(Generator* generator, Symbol* sym, void* liststate, ListClass lc, int uid, size_t count, Bytebuffer* buf, ...)
{
    switch (lc) {
    case LISTCOMPOUND:
    case LISTFIELDARRAY:
	bbAppend(buf,'}');
	break;
    case LISTDATA:
    case LISTVLEN:
    case LISTATTR:
	break;
    }
    return 1;
}

static int
c_vlendecl(Generator* generator, Symbol* tsym, Bytebuffer* codebuf, int uid, size_t count, ...)
{
    /* Build a bytebuffer to capture the vlen decl */
    List* declstack = (List*)generator->globalstate;
    Bytebuffer* decl = bbNew();
    Bytebuffer* vlenbuf;
    va_list ap;
    va_start(ap,count);
    vlenbuf = va_arg(ap, Bytebuffer*);
    va_end(ap);
    bbprintf0(decl,"static const %s vlen_%u[] = {",
	        ctypename(tsym->typ.basetype),
                uid);
    commify(vlenbuf);
    bbCatbuf(decl,vlenbuf);
    bbCat(decl,"} ;");
    listpush(declstack,(void*)decl);
    /* Now generate the reference to buffer */
    bbprintf(codebuf,"{%u,(void*)vlen_%u}",count,uid);
    return 1;
}

static int
c_vlenstring(Generator* generator, Symbol* sym, Bytebuffer* vlenmem, int* uidp, size_t* countp,...)
{
    if(uidp) *uidp = ++c_uid;
    if(countp) *countp = bbLength(vlenmem);
    return 1;
}

/* Define the single static bin data generator  */
static Generator c_generator_singleton = {
    NULL,
    c_charconstant,
    c_constant,
    c_listbegin,
    c_list,
    c_listend,
    c_vlendecl,
    c_vlenstring
};
Generator* c_generator = &c_generator_singleton;

#endif /*ENABLE_C*/
