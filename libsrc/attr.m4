dnl This is m4 source.
dnl Process using m4 to produce 'C' language file.
dnl
dnl If you see this line, you can ignore the next one.
/* Do not edit this file. It is produced from the corresponding .m4 source */
dnl
/*
 *	Copyright 2018, University Corporation for Atmospheric Research
 *      See netcdf/COPYRIGHT file for copying and redistribution conditions.
 */

#if HAVE_CONFIG_H
#include <config.h>
#endif

#include "nc3internal.h"
#include "ncdispatch.h"
#include "nc3dispatch.h"
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include "ncx.h"
#include "fbits.h"
#include "rnd.h"
#include "ncutf8.h"

/*
 * Free attr
 * Formerly
NC_free_attr()
 */
void
free_NC_attr(NC_attr *attrp)
{

	if(attrp == NULL)
		return;
	free_NC_string(attrp->name);
	free(attrp);
}


/*
 * How much space will 'nelems' of 'type' take in
 *  external representation (as the values of an attribute)?
 */
static size_t
ncx_len_NC_attrV(nc_type type, size_t nelems)
{
	switch(type) {
	case NC_BYTE:
	case NC_CHAR:
		return ncx_len_char(nelems);
	case NC_SHORT:
		return ncx_len_short(nelems);
	case NC_INT:
		return ncx_len_int(nelems);
	case NC_FLOAT:
		return ncx_len_float(nelems);
	case NC_DOUBLE:
		return ncx_len_double(nelems);
	case NC_UBYTE:
		return ncx_len_ubyte(nelems);
	case NC_USHORT:
		return ncx_len_ushort(nelems);
	case NC_UINT:
		return ncx_len_uint(nelems);
	case NC_INT64:
		return ncx_len_int64(nelems);
	case NC_UINT64:
		return ncx_len_uint64(nelems);
	default:
	        assert("ncx_len_NC_attr bad type" == 0);
	}
	return 0;
}


NC_attr *
new_x_NC_attr(
	NC_string *strp,
	nc_type type,
	size_t nelems)
{
	NC_attr *attrp;
	const size_t xsz = ncx_len_NC_attrV(type, nelems);
	size_t sz = M_RNDUP(sizeof(NC_attr));

	assert(!(xsz == 0 && nelems != 0));

	sz += xsz;

	attrp = (NC_attr *) malloc(sz);
	if(attrp == NULL )
		return NULL;

	attrp->xsz = xsz;

	attrp->name = strp;
	attrp->type = type;
	attrp->nelems = nelems;
	if(xsz != 0)
		attrp->xvalue = (char *)attrp + M_RNDUP(sizeof(NC_attr));
	else
		attrp->xvalue = NULL;

	return(attrp);
}


/*
 * Formerly
NC_new_attr(name,type,count,value)
 */
static NC_attr *
new_NC_attr(
	const char *uname,
	nc_type type,
	size_t nelems)
{
	NC_string *strp = NULL;
	NC_attr *attrp = NULL;
	char *name = NULL;
	int stat = NC_NOERR;

	stat = nc_utf8_normalize((const unsigned char *)uname,(unsigned char**)&name);
	if(stat != NC_NOERR)
	    goto done;
	assert(name != NULL && *name != 0);

	strp = new_NC_string(strlen(name), name);
	if(strp == NULL)
		goto done;

	attrp = new_x_NC_attr(strp, type, nelems);
	if(attrp == NULL)
	{
		free_NC_string(strp);
		goto done;
	}
done:
	if(name) free(name);
	return (attrp);
}


static NC_attr *
dup_NC_attr(const NC_attr *rattrp)
{
	NC_attr *attrp = new_NC_attr(rattrp->name->cp,
		 rattrp->type, rattrp->nelems);
	if(attrp == NULL)
		return NULL;
        if(attrp->xvalue != NULL && rattrp->xvalue != NULL)
       	    (void) memcpy(attrp->xvalue, rattrp->xvalue, rattrp->xsz);
	return attrp;
}

/* attrarray */

/*
 * Free the stuff "in" (referred to by) an NC_attrarray.
 * Leaves the array itself allocated.
 */
void
free_NC_attrarrayV0(NC_attrarray *ncap)
{
	assert(ncap != NULL);

	if(ncap->nelems == 0)
		return;

	assert(ncap->value != NULL);

	{
		NC_attr **app = ncap->value;
		NC_attr *const *const end = &app[ncap->nelems];
		for( /*NADA*/; app < end; app++)
		{
			free_NC_attr(*app);
			*app = NULL;
		}
	}
	ncap->nelems = 0;
}


/*
 * Free NC_attrarray values.
 * formerly
NC_free_array()
 */
void
free_NC_attrarrayV(NC_attrarray *ncap)
{
	assert(ncap != NULL);

	if(ncap->nalloc == 0)
		return;

	assert(ncap->value != NULL);

	free_NC_attrarrayV0(ncap);

	free(ncap->value);
	ncap->value = NULL;
	ncap->nalloc = 0;
}


int
dup_NC_attrarrayV(NC_attrarray *ncap, const NC_attrarray *ref)
{
	int status = NC_NOERR;

	assert(ref != NULL);
	assert(ncap != NULL);

	if(ref->nelems != 0)
	{
		const size_t sz = ref->nelems * sizeof(NC_attr *);
		ncap->value = (NC_attr **) malloc(sz);
		if(ncap->value == NULL)
			return NC_ENOMEM;

		(void) memset(ncap->value, 0, sz);
		ncap->nalloc = ref->nelems;
	}

	ncap->nelems = 0;
	{
		NC_attr **app = ncap->value;
		const NC_attr **drpp = (const NC_attr **)ref->value;
		NC_attr *const *const end = &app[ref->nelems];
		for( /*NADA*/; app < end; drpp++, app++, ncap->nelems++)
		{
			*app = dup_NC_attr(*drpp);
			if(*app == NULL)
			{
				status = NC_ENOMEM;
				break;
			}
		}
	}

	if(status != NC_NOERR)
	{
		free_NC_attrarrayV(ncap);
		return status;
	}

	assert(ncap->nelems == ref->nelems);

	return NC_NOERR;
}


/*
 * Add a new handle on the end of an array of handles
 * Formerly
NC_incr_array(array, tail)
 */
static int
incr_NC_attrarray(NC_attrarray *ncap, NC_attr *newelemp)
{
	NC_attr **vp;

	assert(ncap != NULL);

	if(ncap->nalloc == 0)
	{
		assert(ncap->nelems == 0);
		vp = (NC_attr **) malloc(NC_ARRAY_GROWBY * sizeof(NC_attr *));
		if(vp == NULL)
			return NC_ENOMEM;

		ncap->value = vp;
		ncap->nalloc = NC_ARRAY_GROWBY;
	}
	else if(ncap->nelems +1 > ncap->nalloc)
	{
		vp = (NC_attr **) realloc(ncap->value,
			(ncap->nalloc + NC_ARRAY_GROWBY) * sizeof(NC_attr *));
		if(vp == NULL)
			return NC_ENOMEM;

		ncap->value = vp;
		ncap->nalloc += NC_ARRAY_GROWBY;
	}

	if(newelemp != NULL)
	{
		ncap->value[ncap->nelems] = newelemp;
		ncap->nelems++;
	}
	return NC_NOERR;
}


NC_attr *
elem_NC_attrarray(const NC_attrarray *ncap, size_t elem)
{
	assert(ncap != NULL);
	/* cast needed for braindead systems with signed size_t */
	if(ncap->nelems == 0 || (unsigned long) elem >= ncap->nelems)
		return NULL;

	assert(ncap->value != NULL);

	return ncap->value[elem];
}

/* End attarray per se */

/*
 * Given ncp and varid, return ptr to array of attributes
 *  else NULL on error
 */
static NC_attrarray *
NC_attrarray0(NC3_INFO* ncp, int varid)
{
	NC_attrarray *ap;

	if(varid == NC_GLOBAL) /* Global attribute, attach to cdf */
	{
		ap = &ncp->attrs;
	}
	else if(varid >= 0 && (size_t) varid < ncp->vars.nelems)
	{
		NC_var **vpp;
		vpp = (NC_var **)ncp->vars.value;
		vpp += varid;
		ap = &(*vpp)->attrs;
	} else {
		ap = NULL;
	}
	return(ap);
}


/*
 * Step thru NC_ATTRIBUTE array, seeking match on name.
 *  return match or NULL if Not Found or out of memory.
 */
NC_attr **
NC_findattr(const NC_attrarray *ncap, const char *uname)
{
	NC_attr **attrpp = NULL;
	size_t attrid;
	size_t slen;
	char *name = NULL;
	int stat = NC_NOERR;

	assert(ncap != NULL);

	if(ncap->nelems == 0)
	    goto done;

	/* normalized version of uname */
	stat = nc_utf8_normalize((const unsigned char *)uname,(unsigned char**)&name);
	if(stat != NC_NOERR)
	    goto done; /* TODO: need better way to indicate no memory */
	slen = strlen(name);

	attrpp = (NC_attr **) ncap->value;
	for(attrid = 0; attrid < ncap->nelems; attrid++, attrpp++)
	{
		if(strlen((*attrpp)->name->cp) == slen &&
			strncmp((*attrpp)->name->cp, name, slen) == 0)
		        goto done;
	}
	attrpp = NULL; /* not found */
done:
        if(name) free(name);
        return (attrpp); /* Normal return */
}


/*
 * Look up by ncid, varid and name, return NULL if not found
 */
static int
NC_lookupattr(int ncid,
	int varid,
	const char *name, /* attribute name */
	NC_attr **attrpp) /* modified on return */
{
	int status;
	NC* nc;
	NC3_INFO *ncp;
	NC_attrarray *ncap;
	NC_attr **tmp;

	status = NC_check_id(ncid, &nc);
	if(status != NC_NOERR)
		return status;
	ncp = NC3_DATA(nc);

	ncap = NC_attrarray0(ncp, varid);
	if(ncap == NULL)
		return NC_ENOTVAR;

	if(name == NULL)
		return NC_EBADNAME;

	tmp = NC_findattr(ncap, name);
	if(tmp == NULL)
		return NC_ENOTATT;

	if(attrpp != NULL)
		*attrpp = *tmp;

	return NC_NOERR;
}

/* Public */

int
NC3_inq_attname(int ncid, int varid, int attnum, char *name)
{
	int status;
	NC* nc;
	NC3_INFO *ncp;
	NC_attrarray *ncap;
	NC_attr *attrp;

	status = NC_check_id(ncid, &nc);
	if(status != NC_NOERR)
		return status;
	ncp = NC3_DATA(nc);

	ncap = NC_attrarray0(ncp, varid);
	if(ncap == NULL)
		return NC_ENOTVAR;

	attrp = elem_NC_attrarray(ncap, (size_t)attnum);
	if(attrp == NULL)
		return NC_ENOTATT;

	(void) strncpy(name, attrp->name->cp, attrp->name->nchars);
	name[attrp->name->nchars] = 0;

	return NC_NOERR;
}


int
NC3_inq_attid(int ncid, int varid, const char *name, int *attnump)
{
	int status;
	NC *nc;
	NC3_INFO* ncp;
	NC_attrarray *ncap;
	NC_attr **attrpp;

	status = NC_check_id(ncid, &nc);
	if(status != NC_NOERR)
		return status;
	ncp = NC3_DATA(nc);

	ncap = NC_attrarray0(ncp, varid);
	if(ncap == NULL)
		return NC_ENOTVAR;


	attrpp = NC_findattr(ncap, name);
	if(attrpp == NULL)
		return NC_ENOTATT;

	if(attnump != NULL)
		*attnump = (int)(attrpp - ncap->value);

	return NC_NOERR;
}

int
NC3_inq_att(int ncid,
	int varid,
	const char *name, /* input, attribute name */
	nc_type *datatypep,
	size_t *lenp)
{
	int status;
	NC_attr *attrp;

	status = NC_lookupattr(ncid, varid, name, &attrp);
	if(status != NC_NOERR)
		return status;

	if(datatypep != NULL)
		*datatypep = attrp->type;
	if(lenp != NULL)
		*lenp = attrp->nelems;

	return NC_NOERR;
}


int
NC3_rename_att( int ncid, int varid, const char *name, const char *unewname)
{
	int status = NC_NOERR;
	NC *nc = NULL;
	NC3_INFO* ncp = NULL;
	NC_attrarray *ncap = NULL;
	NC_attr **tmp = NULL;
	NC_attr *attrp = NULL;
	NC_string *newStr, *old;
	char *newname = NULL;  /* normalized version */

/* start sortof inline clone of NC_lookupattr() */

	status = NC_check_id(ncid, &nc);
	if(status != NC_NOERR)
		goto done;
	ncp = NC3_DATA(nc);

	if(NC_readonly(ncp))
		{status = NC_EPERM; goto done;}

	ncap = NC_attrarray0(ncp, varid);
	if(ncap == NULL)
		{status = NC_ENOTVAR; goto done;}

	status = NC_check_name(unewname);
	if(status != NC_NOERR)
		goto done;

	tmp = NC_findattr(ncap, name);
	if(tmp == NULL)
		{status = NC_ENOTATT; goto done;}
	attrp = *tmp;
/* end inline clone NC_lookupattr() */

	if(NC_findattr(ncap, unewname) != NULL)
	    {status = NC_ENAMEINUSE; goto done;} /* name in use */

	old = attrp->name;
	status = nc_utf8_normalize((const unsigned char *)unewname,(unsigned char**)&newname);
	if(status != NC_NOERR)
	    goto done;
	if(NC_indef(ncp))
	{
		newStr = new_NC_string(strlen(newname), newname);
		if( newStr == NULL)
			{status = NC_ENOMEM; goto done;}
		attrp->name = newStr;
		free_NC_string(old);
		goto done;
	}
	/* else not in define mode */

	/* If new name is longer than old, then complain,
           but otherwise, no change (test is same as set_NC_string)*/
	if(old->nchars < strlen(newname))
	    {status = NC_ENOTINDEFINE; goto done;}

	status = set_NC_string(old, newname);
	if( status != NC_NOERR)
		goto done;

	set_NC_hdirty(ncp);

	if(NC_doHsync(ncp))
	{
		status = NC_sync(ncp);
		if(status != NC_NOERR)
			goto done;
	}
done:
	if(newname) free(newname);
	return status;
}

int
NC3_del_att(int ncid, int varid, const char *uname)
{
	int status = NC_NOERR;
	NC *nc = NULL;
	NC3_INFO* ncp = NULL;
	NC_attrarray *ncap = NULL;
	NC_attr **attrpp = NULL;
	NC_attr *old = NULL;
	int attrid;
	size_t slen;
	char* name = NULL;

	status = NC_check_id(ncid, &nc);
	if(status != NC_NOERR)
		goto done;
	ncp = NC3_DATA(nc);

	if(!NC_indef(ncp))
		{status = NC_ENOTINDEFINE; goto done;}

	ncap = NC_attrarray0(ncp, varid);
	if(ncap == NULL)
		{status = NC_ENOTVAR; goto done;}

	status = nc_utf8_normalize((const unsigned char *)uname,(unsigned char**)&name);
	if(status != NC_NOERR)
	    goto done;

/* start sortof inline NC_findattr() */
	slen = strlen(name);

	attrpp = (NC_attr **) ncap->value;
	for(attrid = 0; (size_t) attrid < ncap->nelems; attrid++, attrpp++)
	    {
		if( slen == (*attrpp)->name->nchars &&
			strncmp(name, (*attrpp)->name->cp, slen) == 0)
		{
			old = *attrpp;
			break;
		}
	    }
	if( (size_t) attrid == ncap->nelems )
		{status = NC_ENOTATT; goto done;}
/* end inline NC_findattr() */

	/* shuffle down */
	for(attrid++; (size_t) attrid < ncap->nelems; attrid++)
	{
		*attrpp = *(attrpp + 1);
		attrpp++;
	}
	*attrpp = NULL;
	/* decrement count */
	ncap->nelems--;

	free_NC_attr(old);

done:
	if(name) free(name);
	return status;
}

dnl
dnl XNCX_PAD_PUTN(Type)
dnl
define(`XNCX_PAD_PUTN',dnl
`dnl
static int
ncx_pad_putn_I$1(void **xpp, size_t nelems, const $1 *tp, nc_type type, void *fillp)
{
	switch(type) {
	case NC_CHAR:
		return NC_ECHAR;
	case NC_BYTE:
		return ncx_pad_putn_schar_$1(xpp, nelems, tp, fillp);
	case NC_SHORT:
		return ncx_pad_putn_short_$1(xpp, nelems, tp, fillp);
	case NC_INT:
		return ncx_putn_int_$1(xpp, nelems, tp, fillp);
	case NC_FLOAT:
		return ncx_putn_float_$1(xpp, nelems, tp, fillp);
	case NC_DOUBLE:
		return ncx_putn_double_$1(xpp, nelems, tp, fillp);
	case NC_UBYTE:
		return ncx_pad_putn_uchar_$1(xpp, nelems, tp, fillp);
	case NC_USHORT:
		return ncx_putn_ushort_$1(xpp, nelems, tp, fillp);
	case NC_UINT:
		return ncx_putn_uint_$1(xpp, nelems, tp, fillp);
	case NC_INT64:
		return ncx_putn_longlong_$1(xpp, nelems, tp, fillp);
	case NC_UINT64:
		return ncx_putn_ulonglong_$1(xpp, nelems, tp, fillp);
	default:
                assert("ncx_pad_putn_I$1 invalid type" == 0);
	}
	return NC_EBADTYPE;
}
')dnl
dnl
dnl XNCX_PAD_GETN(Type)
dnl
define(`XNCX_PAD_GETN',dnl
`dnl
static int
ncx_pad_getn_I$1(const void **xpp, size_t nelems, $1 *tp, nc_type type)
{
	switch(type) {
	case NC_CHAR:
		return NC_ECHAR;
	case NC_BYTE:
		return ncx_pad_getn_schar_$1(xpp, nelems, tp);
	case NC_SHORT:
		return ncx_pad_getn_short_$1(xpp, nelems, tp);
	case NC_INT:
		return ncx_getn_int_$1(xpp, nelems, tp);
	case NC_FLOAT:
		return ncx_getn_float_$1(xpp, nelems, tp);
	case NC_DOUBLE:
		return ncx_getn_double_$1(xpp, nelems, tp);
	case NC_UBYTE:
		return ncx_pad_getn_uchar_$1(xpp, nelems, tp);
	case NC_USHORT:
		return ncx_getn_ushort_$1(xpp, nelems, tp);
	case NC_UINT:
		return ncx_getn_uint_$1(xpp, nelems, tp);
	case NC_INT64:
		return ncx_getn_longlong_$1(xpp, nelems, tp);
	case NC_UINT64:
		return ncx_getn_ulonglong_$1(xpp, nelems, tp);
	default:
	        assert("ncx_pad_getn_I$1 invalid type" == 0);
	}
	return NC_EBADTYPE;
}
')dnl
dnl Implement

XNCX_PAD_PUTN(uchar)
XNCX_PAD_GETN(uchar)

XNCX_PAD_PUTN(schar)
XNCX_PAD_GETN(schar)

XNCX_PAD_PUTN(short)
XNCX_PAD_GETN(short)

XNCX_PAD_PUTN(int)
XNCX_PAD_GETN(int)

XNCX_PAD_PUTN(float)
XNCX_PAD_GETN(float)

XNCX_PAD_PUTN(double)
XNCX_PAD_GETN(double)

#ifdef IGNORE
XNCX_PAD_PUTN(long)
XNCX_PAD_GETN(long)
#endif

XNCX_PAD_PUTN(longlong)
XNCX_PAD_GETN(longlong)

XNCX_PAD_PUTN(ushort)
XNCX_PAD_GETN(ushort)

XNCX_PAD_PUTN(uint)
XNCX_PAD_GETN(uint)

XNCX_PAD_PUTN(ulonglong)
XNCX_PAD_GETN(ulonglong)


/* Common dispatcher for put cases */
static int
dispatchput(void **xpp, size_t nelems, const void* tp,
	    nc_type atype, nc_type memtype, void *fillp)
{
    switch (memtype) {
    case NC_CHAR:
        return ncx_pad_putn_text(xpp,nelems, (char *)tp);
    case NC_BYTE:
        return ncx_pad_putn_Ischar(xpp, nelems, (schar*)tp, atype, fillp);
    case NC_SHORT:
        return ncx_pad_putn_Ishort(xpp, nelems, (short*)tp, atype, fillp);
    case NC_INT:
          return ncx_pad_putn_Iint(xpp, nelems, (int*)tp, atype, fillp);
    case NC_FLOAT:
        return ncx_pad_putn_Ifloat(xpp, nelems, (float*)tp, atype, fillp);
    case NC_DOUBLE:
        return ncx_pad_putn_Idouble(xpp, nelems, (double*)tp, atype, fillp);
    case NC_UBYTE: /*Synthetic*/
        return ncx_pad_putn_Iuchar(xpp,nelems, (uchar *)tp, atype, fillp);
    case NC_INT64:
          return ncx_pad_putn_Ilonglong(xpp, nelems, (longlong*)tp, atype, fillp);
    case NC_USHORT:
          return ncx_pad_putn_Iushort(xpp, nelems, (ushort*)tp, atype, fillp);
    case NC_UINT:
          return ncx_pad_putn_Iuint(xpp, nelems, (uint*)tp, atype, fillp);
    case NC_UINT64:
          return ncx_pad_putn_Iulonglong(xpp, nelems, (ulonglong*)tp, atype, fillp);
    case NC_NAT:
        return NC_EBADTYPE;
    default:
        break;
    }
    return NC_EBADTYPE;
}

int
NC3_put_att(
	int ncid,
	int varid,
	const char *name,
	nc_type type,
	size_t nelems,
	const void *value,
	nc_type memtype)
{
    int status;
    NC *nc;
    NC3_INFO* ncp;
    NC_attrarray *ncap;
    NC_attr **attrpp;
    NC_attr *old = NULL;
    NC_attr *attrp;
    unsigned char fill[8]; /* fill value in internal representation */

    status = NC_check_id(ncid, &nc);
    if(status != NC_NOERR)
	return status;
    ncp = NC3_DATA(nc);

    if(NC_readonly(ncp))
	return NC_EPERM;

    ncap = NC_attrarray0(ncp, varid);
    if(ncap == NULL)
	return NC_ENOTVAR;

    if (name == NULL)
        return NC_EBADNAME;

    /* check NC_EBADTYPE */
    status = nc3_cktype(nc->mode, type);
    if(status != NC_NOERR)
	return status;

    if(memtype == NC_NAT) memtype = type;

    if(memtype != NC_CHAR && type == NC_CHAR)
	return NC_ECHAR;
    if(memtype == NC_CHAR && type != NC_CHAR)
	return NC_ECHAR;

    /* cast needed for braindead systems with signed size_t */
    if((unsigned long) nelems > X_INT_MAX) /* backward compat */
	return NC_EINVAL; /* Invalid nelems */

    if(nelems != 0 && value == NULL)
	return NC_EINVAL; /* Null arg */

    /* Temporarily removed to preserve extant
       workflows (NCO based and others). See

       https://github.com/Unidata/netcdf-c/issues/843

       for more information. */

//    if (varid != NC_GLOBAL && !strcmp(name, _FillValue)) {
//        /* Fill value must be of the same data type */
//        if (type != ncp->vars.value[varid]->type) return NC_EBADTYPE;
//
//        /* Fill value must have exactly one value */
//        if (nelems != 1) return NC_EINVAL;
//
//        /* Only allow for variables defined in initial define mode */
//        if (ncp->old != NULL && varid < ncp->old->vars.nelems)
//            return NC_ELATEFILL; /* try put attribute for an old variable */
//    }

    attrpp = NC_findattr(ncap, name);

    /* 4 cases: exists X indef */

    status = NC3_inq_default_fill_value(type, &fill);
    if (status != NC_NOERR) return status;

    if(attrpp != NULL) { /* name in use */
        if(!NC_indef(ncp)) {
	    const size_t xsz = ncx_len_NC_attrV(type, nelems);
            attrp = *attrpp; /* convenience */

	    if(xsz > attrp->xsz) return NC_ENOTINDEFINE;
	    /* else, we can reuse existing without redef */

	    attrp->xsz = xsz;
            attrp->type = type;
            attrp->nelems = nelems;

            if(nelems != 0) {
                void *xp = attrp->xvalue;
                /* for CDF-1 and CDF-2, NC_BYTE is treated the same type as uchar memtype */
                if (!fIsSet(ncp->flags,NC_64BIT_DATA) && type == NC_BYTE && memtype == NC_UBYTE) {
                    status = NC3_inq_default_fill_value(NC_UBYTE, &fill);
                    if (status != NC_NOERR) return status;
                    status = dispatchput(&xp, nelems, value, memtype, memtype, &fill);
                } else
                    status = dispatchput(&xp, nelems, value, type, memtype, &fill);
            }

            set_NC_hdirty(ncp);

            if(NC_doHsync(ncp)) {
	        const int lstatus = NC_sync(ncp);
                /*
                 * N.B.: potentially overrides NC_ERANGE
                 * set by ncx_pad_putn_I$1
                 */
                if(lstatus != NC_NOERR) return lstatus;
            }

            return status;
        }
        /* else, redefine using existing array slot */
        old = *attrpp;
    } else {
        if(!NC_indef(ncp)) return NC_ENOTINDEFINE;
    }

    status = NC_check_name(name);
    if(status != NC_NOERR) return status;

    attrp = new_NC_attr(name, type, nelems);
    if(attrp == NULL) return NC_ENOMEM;

    if(nelems != 0) {
        void *xp = attrp->xvalue;
        /* for CDF-1 and CDF-2, NC_BYTE is treated the same type as uchar memtype */
        if (!fIsSet(ncp->flags,NC_64BIT_DATA) && type == NC_BYTE && memtype == NC_UBYTE) {
            status = NC3_inq_default_fill_value(NC_UBYTE, &fill);
            if (status != NC_NOERR) return status;
            status = dispatchput(&xp, nelems, (const void*)value, memtype, memtype, &fill);
        } else
            status = dispatchput(&xp, nelems, (const void*)value, type, memtype, &fill);
    }

    if(attrpp != NULL) {
        *attrpp = attrp;
	if(old != NULL)
	        free_NC_attr(old);
    } else {
        const int lstatus = incr_NC_attrarray(ncap, attrp);
        /*
         * N.B.: potentially overrides NC_ERANGE
         * set by ncx_pad_putn_I$1
         */
        if(lstatus != NC_NOERR) {
           free_NC_attr(attrp);
           return lstatus;
        }
    }
    return status;
}

int
NC3_get_att(
	int ncid,
	int varid,
	const char *name,
	void *value,
	nc_type memtype)
{
    int status;
    NC *nc;
    NC3_INFO* ncp;
    NC_attr *attrp;
    const void *xp;

    status = NC_check_id(ncid, &nc);
    if(status != NC_NOERR)
	return status;
    ncp = NC3_DATA(nc);

    status = NC_lookupattr(ncid, varid, name, &attrp);
    if(status != NC_NOERR) return status;

    if(attrp->nelems == 0) return NC_NOERR;

    if(memtype == NC_NAT) memtype = attrp->type;

    if(memtype != NC_CHAR && attrp->type == NC_CHAR)
	return NC_ECHAR;
    if(memtype == NC_CHAR && attrp->type != NC_CHAR)
	return NC_ECHAR;

    xp = attrp->xvalue;
    switch (memtype) {
    case NC_CHAR:
        return ncx_pad_getn_text(&xp, attrp->nelems, (char *)value);
    case NC_BYTE:
        return ncx_pad_getn_Ischar(&xp,attrp->nelems,(schar*)value,attrp->type);
    case NC_SHORT:
        return ncx_pad_getn_Ishort(&xp,attrp->nelems,(short*)value,attrp->type);
    case NC_INT:
          return ncx_pad_getn_Iint(&xp,attrp->nelems,(int*)value,attrp->type);
    case NC_FLOAT:
        return ncx_pad_getn_Ifloat(&xp,attrp->nelems,(float*)value,attrp->type);
    case NC_DOUBLE:
        return ncx_pad_getn_Idouble(&xp,attrp->nelems,(double*)value,attrp->type);
    case NC_INT64:
          return ncx_pad_getn_Ilonglong(&xp,attrp->nelems,(longlong*)value,attrp->type);
    case NC_UBYTE: /* Synthetic */
        /* for CDF-1 and CDF-2, NC_BYTE is treated the same type as uchar memtype */
        if (!fIsSet(ncp->flags,NC_64BIT_DATA) && attrp->type == NC_BYTE)
            return ncx_pad_getn_Iuchar(&xp, attrp->nelems, (uchar *)value, NC_UBYTE);
        else
            return ncx_pad_getn_Iuchar(&xp, attrp->nelems, (uchar *)value, attrp->type);
    case NC_USHORT:
          return ncx_pad_getn_Iushort(&xp,attrp->nelems,(ushort*)value,attrp->type);
    case NC_UINT:
          return ncx_pad_getn_Iuint(&xp,attrp->nelems,(uint*)value,attrp->type);
    case NC_UINT64:
          return ncx_pad_getn_Iulonglong(&xp,attrp->nelems,(ulonglong*)value,attrp->type);
    case NC_NAT:
        return NC_EBADTYPE;
    default:
        break;
    }
    status =  NC_EBADTYPE;
    return status;
}
