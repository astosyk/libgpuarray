cimport libc.stdio
from libc.stdlib cimport calloc, free
cimport numpy as np

from cpython cimport Py_INCREF, PyNumber_Index

np.import_array()

cdef extern from "stdarg.h":
    ctypedef struct va_list:
        pass
    # I only need "int" for this
    void va_start(va_list, int)
    void va_end(va_list)

cdef extern from "numpy/arrayobject.h":
    object _PyArray_Empty "PyArray_Empty" (int, np.npy_intp *, np.dtype, int)

# Numpy API steals dtype references and this breaks cython
cdef object PyArray_Empty(int a, np.npy_intp *b, np.dtype c, int d):
    Py_INCREF(c)
    return _PyArray_Empty(a, b, c, d)

cdef extern from "Python.h":
    cdef int PySlice_GetIndicesEx(slice slice, Py_ssize_t length,
                                  Py_ssize_t *start, Py_ssize_t *stop,
                                  Py_ssize_t *step,
                                  Py_ssize_t *slicelength) except -1

# This is a horrible hack to introduce ifdefs in cython code.
cdef extern from *:
    void cifcuda "#ifdef WITH_CUDA //" ()
    void cifopencl "#ifdef WITH_OPENCL //" ()
    void cendif "#endif //" ()

cdef extern from "compyte_util.h":
     size_t compyte_get_elsize(int typecode)

cdef extern from "compyte_buffer.h":
    ctypedef struct gpudata:
        pass
    ctypedef struct gpukernel:
        pass

    ctypedef struct compyte_buffer_ops:
        void *buffer_init(int devno, int *ret)
        char *buffer_error()

    compyte_buffer_ops cuda_ops
    compyte_buffer_ops opencl_ops

    ctypedef struct _GpuArray "GpuArray":
        gpudata *data
        compyte_buffer_ops *ops
        size_t *dimensions
        ssize_t *strides
        unsigned int nd
        int flags
        int typecode

    ctypedef struct _GpuKernel "GpuKernel":
       gpukernel *k
       compyte_buffer_ops *ops

    cdef int GA_C_CONTIGUOUS
    cdef int GA_F_CONTIGUOUS
    cdef int GA_OWNDATA
    cdef int GA_ENSURECOPY
    cdef int GA_ALIGNED
    cdef int GA_WRITEABLE
    cdef int GA_BEHAVED
    cdef int GA_CARRAY
    cdef int GA_FARRAY

    bint GpuArray_CHKFLAGS(_GpuArray *a, int fl)
    bint GpuArray_ISONESEGMENT(_GpuArray *a)

    ctypedef enum ga_order:
        GA_ANY_ORDER, GA_C_ORDER, GA_F_ORDER

    cdef enum ga_error:
        GA_NO_ERROR, GA_MEMORY_ERROR, GA_VALUE_ERROR, GA_IMPL_ERROR,
        GA_INVALID_ERROR, GA_UNSUPPORTED_ERROR, GA_SYS_ERROR

    enum COMPYTE_TYPES:
        GA_INT,
        GA_UINT,
        GA_LONG,
        GA_ULONG,
        GA_FLOAT,
        GA_DOUBLE,
        GA_NBASE

    char *Gpu_error(compyte_buffer_ops *o, int err) nogil

    int GpuArray_empty(_GpuArray *a, compyte_buffer_ops *ops, void *ctx,
                       int typecode, int nd, size_t *dims, ga_order ord) nogil
    int GpuArray_zeros(_GpuArray *a, compyte_buffer_ops *ops, void *ctx,
                       int typecode, int nd, size_t *dims, ga_order ord) nogil
    int GpuArray_view(_GpuArray *v, _GpuArray *a) nogil
    int GpuArray_index(_GpuArray *r, _GpuArray *a, ssize_t *starts,
                       ssize_t *stops, ssize_t *steps) nogil

    void GpuArray_clear(_GpuArray *a) nogil

    int GpuArray_share(_GpuArray *a, _GpuArray *b) nogil

    int GpuArray_move(_GpuArray *dst, _GpuArray *src) nogil
    int GpuArray_write(_GpuArray *dst, void *src, size_t src_sz) nogil
    int GpuArray_read(void *dst, size_t dst_sz, _GpuArray *src) nogil
    int GpuArray_memset(_GpuArray *a, int data) nogil

    char *GpuArray_error(_GpuArray *a, int err) nogil
    
    void GpuArray_fprintf(libc.stdio.FILE *fd, _GpuArray *a) nogil
    int GpuArray_is_c_contiguous(_GpuArray *a) nogil
    int GpuArray_is_f_contiguous(_GpuArray *a) nogil

    int GpuKernel_init(_GpuKernel *k, compyte_buffer_ops *ops, void *ctx,
                       unsigned int count, char **strs, size_t *lens,
                       char *name) nogil
    void GpuKernel_clear(_GpuKernel *k) nogil
    int GpuKernel_setargv(_GpuKernel *k, unsigned int index, int typecode,
                          va_list ap) nogil
    int GpuKernel_setbufarg(_GpuKernel *k, unsigned int index,
                            _GpuArray *a) nogil
    int GpuKernel_setrawarg(_GpuKernel *k, unsigned int index, size_t sz,
                            void *val) nogil
    int GpuKernel_call(_GpuKernel *, unsigned int gx, unsigned int gy,
                       unsigned int gz, unsigned int lx, unsigned int ly,
                       unsigned int lz) nogil

cdef object call_compiler = None
cdef extern int call_compiler_unix(char *fname, char *oname)

cdef public int call_compiler_python(char *fname, char *oname) with gil:
    if call_compiler is None:
        return call_compiler_unix(fname, oname)
    else:
        try:
            return call_compiler(fname, oname)
        except:
            # This would correspond to an unknown error
            # XXX: maybe should store the exception somewhere
            return -1

def set_compiler_fn(fn):
    if callable(fn) or fn is None:
        call_compiler = fn
    else:
        raise ValueError("need a callable")

import numpy

cdef int dtype_to_typecode(dtype):
    cdef int dnum
    if isinstance(dtype, int):
        return dtype
    if isinstance(dtype, str):
        dtype = np.dtype(dtype)
    if isinstance(dtype, np.dtype):
        dnum = (<np.dtype>dtype).type_num
        if dnum < GA_NBASE:
            return dnum
    raise ValueError("don't know how to convert to dtype: %s"%(dtype,))

cdef int to_ga_order(ord):
    if ord == "C":
        return GA_C_ORDER
    elif ord == "A":
        return GA_ANY_ORDER
    elif ord == "F":
        return GA_F_ORDER
    else:
        raise ValueError("Valid orders are: 'A' (any), 'C' (C), 'F' (Fortran)")

class GpuArrayException(Exception):
    pass

cdef bint py_CHKFLAGS(GpuArray a, int flags):
    return GpuArray_CHKFLAGS(&a.ga, flags)

cdef bint py_ISONESEGMENT(GpuArray a):
    return GpuArray_ISONESEGMENT(&a.ga)

cdef array_empty(GpuArray a, compyte_buffer_ops *ops, void *ctx, int typecode,
            unsigned int nd, size_t *dims, ga_order ord):
    cdef int err
    with nogil:
        err = GpuArray_empty(&a.ga, ops, ctx, typecode, nd, dims, ord)
    if err != GA_NO_ERROR:
        raise GpuArrayException(GpuArray_error(&a.ga, err))

cdef array_zeros(GpuArray a, compyte_buffer_ops *ops, void *ctx, int typecode,
            unsigned int nd, size_t *dims, ga_order ord):
    cdef int err
    with nogil:
        err = GpuArray_zeros(&a.ga, ops, ctx, typecode, nd, dims, ord)
    if err != GA_NO_ERROR:
        raise GpuArrayException(GpuArray_error(&a.ga, err))

cdef array_view(GpuArray v, GpuArray a):
    cdef int err
    with nogil:
        err = GpuArray_view(&v.ga, &a.ga)
    if err != GA_NO_ERROR:
        raise GpuArrayException(GpuArray_error(&a.ga, err))

cdef array_index(GpuArray r, GpuArray a, ssize_t *starts, ssize_t *stops,
            ssize_t *steps):
    cdef int err
    with nogil:
        err = GpuArray_index(&r.ga, &a.ga, starts, stops, steps)
    if err != GA_NO_ERROR:
        raise GpuArrayException(GpuArray_error(&a.ga, err))

cdef array_clear(GpuArray a):
    with nogil:
        GpuArray_clear(&a.ga)

cdef bint array_share(GpuArray a, GpuArray b):
    cdef int res
    with nogil:
        res = GpuArray_share(&a.ga, &b.ga);
    return res

cdef array_move(GpuArray a, GpuArray src):
    cdef int err
    with nogil:
        err = GpuArray_move(&a.ga, &src.ga)
    if err != GA_NO_ERROR:
        raise GpuArrayException(GpuArray_error(&a.ga, err))

cdef array_write(GpuArray a, void *src, size_t sz):
    cdef int err
    with nogil:
        err = GpuArray_write(&a.ga, src, sz)
    if err != GA_NO_ERROR:
        raise GpuArrayException(GpuArray_error(&a.ga, err))

cdef array_read(void *dst, size_t sz, GpuArray src):
    cdef int err
    with nogil:
        err = GpuArray_read(dst, sz, &src.ga)
    if err != GA_NO_ERROR:
        raise GpuArrayException(GpuArray_error(&src.ga, err))

cdef array_memset(GpuArray a, int data):
    cdef int err
    with nogil:
        err = GpuArray_memset(&a.ga, data)
    if err != GA_NO_ERROR:
        raise GpuArrayException(GpuArray_error(&a.ga, err))

cdef kernel_init(GpuKernel k, compyte_buffer_ops *ops, void *ctx,
                 unsigned int count, char **strs, size_t *len, char *name):
    cdef int err
    with nogil:
        err = GpuKernel_init(&k.k, ops, ctx, count, strs, len, name)
    if err != GA_NO_ERROR:
        raise GpuArrayException(Gpu_error(ops, err))

cdef kernel_clear(GpuKernel k):
    with nogil:
        GpuKernel_clear(&k.k)

cdef kernel_setarg(GpuKernel k, unsigned int index, int typecode, ...):
    cdef int err
    cdef va_list ap
    va_start(ap, typecode);
    with nogil:
        err = GpuKernel_setargv(&k.k, index, typecode, ap)
    va_end(ap)
    if err != GA_NO_ERROR:
        raise GpuArrayException(Gpu_error(k.k.ops, err))

cdef kernel_setbufarg(GpuKernel k, unsigned int index, GpuArray a):
    cdef int err
    with nogil:
        err = GpuKernel_setbufarg(&k.k, index, &a.ga)
    if err != GA_NO_ERROR:
        raise GpuArrayException(Gpu_error(k.k.ops, err))

cdef kernel_call(GpuKernel k, unsigned int gx, unsigned int gy,
                 unsigned int gz, unsigned int lx, unsigned int ly,
                 unsigned int lz):
    cdef int err
    with nogil:
        err = GpuKernel_call(&k.k, gx, gy, gz, lx, ly, lz)
    if err != GA_NO_ERROR:
        raise GpuArrayException(Gpu_error(k.k.ops, err))


cdef compyte_buffer_ops *GpuArray_ops
cdef void *GpuArray_ctx

def set_kind_context(kind, size_t ctx):
    global GpuArray_ctx
    global GpuArray_ops
    GpuArray_ctx = <void *>ctx
    cifcuda()
    if kind == "cuda":
        GpuArray_ops = &cuda_ops
        return
    cendif()
    cifopencl()
    if kind == "opencl":
        GpuArray_ops = &opencl_ops
        return
    cendif()
    raise ValueError("Unknown kind")

def init(kind, int devno):
    cdef int err = GA_NO_ERROR
    cdef void *ctx
    ctx = NULL
    cifopencl()
    if kind == "opencl":
        ctx = opencl_ops.buffer_init(devno, &err)
        if (err != GA_NO_ERROR):
            if err == GA_VALUE_ERROR:
                raise GpuArrayException("No device %d"%(devno,))
            else:
                raise GpuArrayException(opencl_ops.buffer_error())
    cendif()
    cifcuda()
    if kind == "cuda":
        ctx = cuda_ops.buffer_init(devno, &err)
        if (err != GA_NO_ERROR):
            if err == GA_VALUE_ERROR:
                raise GpuArrayException("No device %d"%(devno,))
            else:
                raise GpuArrayException(cuda_ops.buffer_error())
    cendif()
    if ctx == NULL:
        raise RuntimeError("Unsupported kind: %s"%(kind,))
    return <size_t>ctx

def zeros(shape, dtype=GA_DOUBLE, order='A'):
    return GpuArray(shape, dtype=dtype, order=order, memset=0)

def empty(shape, dtype=GA_DOUBLE, order='A'):
    return GpuArray(shape, dtype=dtype, order=order)

def may_share_memory(GpuArray a not None, GpuArray b not None):
    return array_share(a, b)

cdef class GpuArray:
    cdef _GpuArray ga
    cdef readonly object base

    def __dealloc__(self):
        array_clear(self)

    def __cinit__(self, *a, **kwa):
        cdef size_t *cdims

        if len(a) == 1:
            proto = a[0]
            if isinstance(proto, np.ndarray):
                self.from_array(proto)
            elif isinstance(proto, GpuArray):
                if 'view' in kwa and kwa['view']:
                    self.make_view(proto)
                elif 'index' in kwa:
                    self.make_index(proto, kwa['index'])
                else:
                    self.make_copy(proto, kwa.get('dtype',
                                                  (<GpuArray>proto).ga.typecode),
                                   to_ga_order(kwa.get('order', 'A')))
            elif isinstance(proto, (list, tuple)):
                cdims = <size_t *>calloc(len(proto), sizeof(size_t));
                if cdims == NULL:
                    raise MemoryError("could not allocate cdims")
                for i, d in enumerate(proto):
                    cdims[i] = d

                try:
                    self.make_empty(len(proto), cdims,
                                    kwa.get('dtype', GA_FLOAT),
                                    to_ga_order(kwa.get('order', 'A')))
                finally:
                    free(cdims)
                if 'memset' in kwa:
                    fill = kwa['memset']
                    if fill is not None:
                        self.memset(fill)
        else:
            raise ValueError("Cannot initialize from the given arguments", a, kwa)
    
    cdef make_empty(self, unsigned int nd, size_t *dims, dtype, ord):
        array_empty(self, GpuArray_ops, GpuArray_ctx, dtype_to_typecode(dtype),
                    nd, dims, ord)

    cdef make_copy(self, GpuArray other, dtype, ord):
        if ord == GA_ANY_ORDER:
            if py_CHKFLAGS(other, GA_F_CONTIGUOUS) and \
                    not py_CHKFLAGS(other, GA_C_CONTIGUOUS):
                ord = GA_F_ORDER
            else:
                ord = GA_C_ORDER
        self.make_empty(other.ga.nd, other.ga.dimensions, dtype, ord)
        array_move(self, other)

    cdef make_view(self, GpuArray other):
        array_view(self, other)
        base = other
        while base.base is not None:
            base = base.base
        self.base = base

    cdef __index_helper(self, key, unsigned int i, ssize_t *start,
                        ssize_t *stop, ssize_t *step):
        cdef Py_ssize_t dummy
        cdef Py_ssize_t k
        try:
            k = PyNumber_Index(key)
            if k < 0:
                k += self.ga.dimensions[i]
            if k < 0 or k >= self.ga.dimensions[i]:
                raise IndexError("index %d out of bounds"%(i,))
            start[0] = k
            step[0] = 0
            return
        except TypeError:
            pass

        if isinstance(key, slice):
            PySlice_GetIndicesEx(key, self.ga.dimensions[i], start, stop,
                                 step, &dummy)
            if stop[0] < start[0] and step[0] > 0:
                stop[0] = start[0]
        elif key is Ellipsis:
            start[0] = 0
            stop[0] = self.ga.dimensions[i]
            step[0] = 1
        else:
            raise IndexError("cannot index with: %s"%(key,))

    cdef make_index(self, GpuArray other, key):
        cdef ssize_t *starts
        cdef ssize_t *stops
        cdef ssize_t *steps
        cdef unsigned int i
        cdef unsigned int d

        starts = <ssize_t *>calloc(other.ga.nd, sizeof(ssize_t))
        stops = <ssize_t *>calloc(other.ga.nd, sizeof(ssize_t))
        steps = <ssize_t *>calloc(other.ga.nd, sizeof(ssize_t))
        try:
            if starts == NULL or stops == NULL or steps == NULL:
                raise MemoryError()

            d = 0

            if isinstance(key, tuple):
                if len(key) > other.ga.nd:
                    raise IndexError("invalid index")
                for i in range(0, len(key)):
                    other.__index_helper(key[i], i, &starts[i], &stops[i],
                                         &steps[i])
                d += len(key)
            else:
                other.__index_helper(key, 0, starts, stops, steps)
                d += 1

            for i in range(d, other.ga.nd):
                starts[i] = 0
                stops[i] = other.ga.dimensions[i]
                steps[i] = 1

            array_index(self, other, starts, stops, steps);
        finally:
            free(starts)
            free(stops)
            free(steps)

    def memset(self, value):
        array_memset(self, value)
    
    cdef from_array(self, np.ndarray a):
        if not np.PyArray_ISONESEGMENT(a):
            a = np.PyArray_ContiguousFromAny(a, np.PyArray_TYPE(a),
                                             np.PyArray_NDIM(a),
                                             np.PyArray_NDIM(a))

        if np.PyArray_ISFORTRAN(a) and not np.PyArray_ISCONTIGUOUS(a):
            order = GA_F_ORDER
        else:
            order = GA_C_ORDER
        self.make_empty(np.PyArray_NDIM(a), <size_t *>np.PyArray_DIMS(a),
                        a.dtype, order)

        array_write(self, np.PyArray_DATA(a), np.PyArray_NBYTES(a))

    def __array__(self):
        cdef np.ndarray res
        
        if not py_ISONESEGMENT(self):
            self = self.copy()

        res = PyArray_Empty(self.ga.nd, <np.npy_intp *>self.ga.dimensions,
                            self.dtype, py_CHKFLAGS(self, GA_F_CONTIGUOUS) \
                                and not py_CHKFLAGS(self, GA_C_CONTIGUOUS))
        
        array_read(np.PyArray_DATA(res),
                   np.PyArray_NBYTES(res),
                   self)
        
        return res

    def copy(self, dtype=None, order='A'):
        if dtype is None:
            dtype = self.ga.typecode
        return GpuArray(self, dtype=dtype, order=order)

    def __copy__(self):
        return GpuArray(self)

    def __deepcopy__(self, memo):
        if id(self) in memo:
            return memo[id(self)]
        else:
            return GpuArray(self)

    def view(self):
        return GpuArray(self, view=True)

    def __len__(self):
        if self.ga.nd > 0:
            return self.ga.dimensions[0]
        else:
            raise TypeError("len() of unsized object")

    def __getitem__(self, key):
        if key is Ellipsis:
            return self
        elif self.ga.nd == 0:
            raise IndexError("0-d arrays can't be indexed")
        return GpuArray(self, index=key)

    property shape:
        "shape of this ndarray (tuple)"
        def __get__(self):
            cdef unsigned int i
            res = [None] * self.ga.nd
            for i in range(self.ga.nd):
                res[i] = self.ga.dimensions[i]
            return tuple(res)

        def __set__(self, newshape):
            raise NotImplementedError("TODO: call reshape")

    property size:
        "The number of elements in this object."
        def __get__(self):
            cdef size_t res = 1
            cdef unsigned int i
            for i in range(self.ga.nd):
                res *= self.ga.dimensions[i]
            return res

    property strides:
        "data pointer strides (in bytes)"
        def __get__(self):
            cdef unsigned int i
            res = [None] * self.ga.nd
            for i in range(self.ga.nd):
                res[i] = self.ga.strides[i]
            return tuple(res)
        
    property ndim:
        "The number of dimensions in this object"
        def __get__(self):
            return self.ga.nd
        
    property dtype:
        "The dtype of the element"
        def __get__(self):
            # XXX: will have to figure out the right numpy dtype
            if self.ga.typecode < GA_NBASE:
                return np.PyArray_DescrFromType(self.ga.typecode)
            else:
                raise NotImplementedError("TODO")

    property itemsize:
        "The size of the base element."
        def __get__(self):
            return compyte_get_elsize(self.ga.typecode)
    
    property flags:
        "Return the flags as a dictionary"
        def __get__(self):
            res = dict()
            res["C_CONTIGUOUS"] = py_CHKFLAGS(self, GA_C_CONTIGUOUS)
            res["F_CONTIGUOUS"] = py_CHKFLAGS(self, GA_F_CONTIGUOUS)
            res["WRITEABLE"] = py_CHKFLAGS(self, GA_WRITEABLE)
            res["ALIGNED"] = py_CHKFLAGS(self, GA_ALIGNED)
            res["UPDATEIFCOPY"] = False # Unsupported
            res["OWNDATA"] = py_CHKFLAGS(self, GA_OWNDATA)
            return res

cdef class GpuKernel:
    cdef _GpuKernel k
    
    def __dealloc__(self):
        kernel_clear(self)

    def __cinit__(self, source, name, *a, **kwa):
        cdef char *s[1]
        cdef size_t l
        
        if not isinstance(source, (str, unicode)):
            raise TypeError("Expected a string for the kernel source")
        if not isinstance(source, (str, unicode)):
            raise TypeError("Expected a string for the kernel name")

        # This is required under CUDA otherwise the function is compiled
        # as a C++ mangled name and is irretriveable
        # XXX: I don't know if it works in OpenCL, and can't test for now.
        ss = 'extern "C" {%s}'%(source,)

        s[0] = ss
        l = len(ss)
        kernel_init(self, GpuArray_ops, GpuArray_ctx, 1, s, &l, name);

    def __call__(self, *args, grid=None, block=None):
        if block is None:
            raise ValueError("Must specify block")
        if grid is None:
            raise ValueError("Must specify grid")

        block = tuple(block)
        grid = tuple(grid)

        if len(block) < 3:
            block = block + (1,) * (3 - len(block))
        if len(grid) < 3:
            grid = grid + (1,) * (3 - len(grid))

        if len(block) != 3:
            raise ValueError("len(block) != 3")
        if len(grid) != 3:
            raise ValueError("len(grid) != 3")

        # Work backwards to avoid a lot of reallocations in the argument code.
        for i in range(len(args)-1, -1, -1):
            self.setarg(i, args[i])

        self.call(*(grid+block))
        
    def setarg(self, unsigned int index, o):
        if isinstance(o, GpuArray):
            self.setbufarg(index, o)
        else:
            # this will break for object that are not numpy-like, but meh.
            self._setarg(index, o.dtype, o)

    def setbufarg(self, unsigned int index, GpuArray a not None):
        kernel_setbufarg(self, index, a)

    cdef _setarg(self, unsigned int index, np.dtype t, object o):
        cdef double d
        cdef int i
        cdef unsigned int ui
        cdef long l
        cdef unsigned long ul
        cdef unsigned int typecode
        typecode = dtype_to_typecode(t)
        if typecode == GA_FLOAT or typecode == GA_DOUBLE:
            d = o
            kernel_setarg(self, index, typecode, d)
        elif typecode == GA_INT:
            i = o
            kernel_setarg(self, index, typecode, i)
        elif typecode == GA_UINT:
            ui = o
            kernel_setarg(self, index, typecode, ui)
        elif typecode == GA_LONG:
            l = o
            kernel_setarg(self, index, typecode, l)
        elif typecode == GA_ULONG:
            ul = o
            kernel_setarg(self, index, typecode, ul)
        else:
            raise ValueError("Can't set argument of this type")

    def call(self, unsigned int gx, unsigned int gy, unsigned int gz,
             unsigned int lx, unsigned int ly, unsigned int lz):
        kernel_call(self, gx, gy, gz, lx, ly, lz)
