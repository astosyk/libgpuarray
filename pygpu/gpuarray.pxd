cimport libc

# This is used in a hack to silence some over-eager warnings.
cdef extern from *:
    ctypedef object slice_object "PySliceObject *"

cdef extern from "stdlib.h":
    void *memcpy(void *dst, void *src, size_t n)
    void *memset(void *b, int c, size_t sz)

cimport numpy as np

cdef extern from "numpy/arrayobject.h":
    object _PyArray_Empty "PyArray_Empty" (int, np.npy_intp *, np.dtype, int)

cdef object PyArray_Empty(int a, np.npy_intp *b, np.dtype c, int d)

cdef extern from "Python.h":
    int PySlice_GetIndicesEx(object slice, Py_ssize_t length,
                             Py_ssize_t *start, Py_ssize_t *stop,
                             Py_ssize_t *step,
                             Py_ssize_t *slicelength) except -1

cdef extern from "gpuarray/config.h":
    int GPUARRAY_API_VERSION
    int GPUARRAY_ABI_VERSION

cdef extern from "gpuarray/types.h":
    ctypedef struct gpuarray_type:
        const char *cluda_name
        size_t size
        size_t align
        int typecode

    enum GPUARRAY_TYPES:
        GA_BUFFER,
        GA_BOOL,
        GA_BYTE,
        GA_UBYTE,
        GA_SHORT,
        GA_USHORT,
        GA_INT,
        GA_UINT,
        GA_LONG,
        GA_ULONG,
        GA_FLOAT,
        GA_DOUBLE,
        GA_CFLOAT,
        GA_CDOUBLE,
        GA_HALF,
        GA_SIZE,
        GA_SSIZE,
        GA_NBASE

cdef extern from "gpuarray/util.h":
    int gpuarray_register_type(gpuarray_type *t, int *ret)
    size_t gpuarray_get_elsize(int typecode)
    gpuarray_type *gpuarray_get_type(int typecode)

cdef extern from "gpuarray/error.h":
    cdef enum ga_error:
        GA_NO_ERROR, GA_MEMORY_ERROR, GA_VALUE_ERROR, GA_IMPL_ERROR,
        GA_INVALID_ERROR, GA_UNSUPPORTED_ERROR, GA_SYS_ERROR, GA_RUN_ERROR,
        GA_DEVSUP_ERROR, GA_READONLY_ERROR, GA_WRITEONLY_ERROR, GA_BLAS_ERROR,
        GA_UNALIGNED_ERROR, GA_COPY_ERROR, GA_COMM_ERROR

cdef extern from "gpuarray/buffer.h":
    ctypedef struct gpucontext_props:
        pass
    ctypedef struct gpucontext:
        pass
    ctypedef struct gpudata:
        pass
    ctypedef struct gpukernel:
        pass

    int gpu_get_platform_count(const char* name, unsigned int* platcount)
    int gpu_get_device_count(const char* name, unsigned int platform, unsigned int* devcount)

    int gpucontext_props_new(gpucontext_props **res)
    int gpucontext_props_cuda_dev(gpucontext_props *p, int devno)
    int gpucontext_props_opencl_dev(gpucontext_props *p, int platno, int devno)
    int gpucontext_props_sched(gpucontext_props *p, int sched)
    int gpucontext_props_set_single_stream(gpucontext_props *p)
    int gpucontext_props_kernel_cache(gpucontext_props *p, const char *path)
    int gpucontext_props_alloc_cache(gpucontext_props *p, size_t initial, size_t max)
    void gpucontext_props_del(gpucontext_props *p)

    int gpucontext_init(gpucontext **res, const char *name, gpucontext_props *p)
    void gpucontext_deref(gpucontext *ctx)
    char *gpucontext_error(gpucontext *ctx, int err)
    int gpudata_property(gpudata *ctx, int prop_id, void *res)
    int gpucontext_property(gpucontext *ctx, int prop_id, void *res)
    int gpukernel_property(gpukernel *k, int prop_id, void *res)
    gpucontext *gpudata_context(gpudata *)
    gpucontext *gpukernel_context(gpukernel *)

    int GA_CTX_SCHED_AUTO
    int GA_CTX_SCHED_SINGLE
    int GA_CTX_SCHED_MULTI

    int GA_CTX_PROP_DEVNAME
    int GA_CTX_PROP_UNIQUE_ID
    int GA_CTX_PROP_LMEMSIZE
    int GA_CTX_PROP_NUMPROCS
    int GA_CTX_PROP_BIN_ID
    int GA_CTX_PROP_TOTAL_GMEM
    int GA_CTX_PROP_FREE_GMEM
    int GA_CTX_PROP_MAXLSIZE0
    int GA_CTX_PROP_MAXLSIZE1
    int GA_CTX_PROP_MAXLSIZE2
    int GA_CTX_PROP_MAXGSIZE0
    int GA_CTX_PROP_MAXGSIZE1
    int GA_CTX_PROP_MAXGSIZE2
    int GA_CTX_PROP_LARGEST_MEMBLOCK

    int GA_BUFFER_PROP_SIZE

    int GA_KERNEL_PROP_MAXLSIZE
    int GA_KERNEL_PROP_PREFLSIZE
    int GA_KERNEL_PROP_NUMARGS
    int GA_KERNEL_PROP_TYPES

    cdef enum ga_usefl:
        GA_USE_SMALL, GA_USE_DOUBLE, GA_USE_COMPLEX, GA_USE_HALF,
        GA_USE_CUDA, GA_USE_OPENCL

cdef extern from "gpuarray/kernel.h":
    ctypedef struct _GpuKernel "GpuKernel":
        gpukernel *k

    int GpuKernel_init(_GpuKernel *k, gpucontext *ctx,
                       unsigned int count, const char **strs,
                       const size_t *lens, const char *name,
                       unsigned int argcount, const int *types, int flags, char **err_str)
    void GpuKernel_clear(_GpuKernel *k)
    gpucontext *GpuKernel_context(_GpuKernel *k)
    int GpuKernel_sched(_GpuKernel *k, size_t n, size_t *gs, size_t *ls)
    int GpuKernel_call(_GpuKernel *k, unsigned int n,
                       const size_t *gs, const size_t *ls,
                       size_t shared, void **args)

cdef extern from "gpuarray/array.h":
    ctypedef struct _GpuArray "GpuArray":
        gpudata *data
        size_t offset
        size_t *dimensions
        ssize_t *strides
        unsigned int nd
        int flags
        int typecode

    cdef int GA_C_CONTIGUOUS
    cdef int GA_F_CONTIGUOUS
    cdef int GA_ALIGNED
    cdef int GA_WRITEABLE
    cdef int GA_BEHAVED
    cdef int GA_CARRAY
    cdef int GA_FARRAY

    bint GpuArray_CHKFLAGS(_GpuArray *a, int fl)
    bint GpuArray_ISONESEGMENT(_GpuArray *a)
    bint GpuArray_IS_C_CONTIGUOUS(_GpuArray *a)

    ctypedef enum ga_order:
        GA_ANY_ORDER, GA_C_ORDER, GA_F_ORDER

    void GpuArray_fix_flags(_GpuArray *a)
    int GpuArray_empty(_GpuArray *a, gpucontext *ctx,
                       int typecode, int nd, const size_t *dims, ga_order ord)
    int GpuArray_fromdata(_GpuArray *a,
                          gpudata *data, size_t offset, int typecode,
                          unsigned int nd, const size_t *dims,
                          const ssize_t *strides, int writable)
    int GpuArray_view(_GpuArray *v, _GpuArray *a)
    int GpuArray_sync(_GpuArray *a) nogil
    int GpuArray_index(_GpuArray *r, _GpuArray *a, const ssize_t *starts,
                       const ssize_t *stops, const ssize_t *steps)
    int GpuArray_take1(_GpuArray *r, _GpuArray *a, _GpuArray *i, int check_err)
    int GpuArray_setarray(_GpuArray *v, _GpuArray *a)
    int GpuArray_reshape(_GpuArray *res, _GpuArray *a, unsigned int nd,
                         const size_t *newdims, ga_order ord, int nocopy)
    int GpuArray_reshape_inplace(_GpuArray *a, unsigned int nd,
                                 const size_t *newdims, ga_order ord)
    int GpuArray_transpose(_GpuArray *res, _GpuArray *a,
                           const unsigned int *new_axes)

    void GpuArray_clear(_GpuArray *a)

    int GpuArray_share(_GpuArray *a, _GpuArray *b)
    gpucontext *GpuArray_context(_GpuArray *a)

    int GpuArray_move(_GpuArray *dst, _GpuArray *src)
    int GpuArray_write(_GpuArray *dst, void *src, size_t src_sz) nogil
    int GpuArray_read(void *dst, size_t dst_sz, _GpuArray *src) nogil
    int GpuArray_memset(_GpuArray *a, int data)
    int GpuArray_copy(_GpuArray *res, _GpuArray *a, ga_order order)

    int GpuArray_transfer(_GpuArray *res, const _GpuArray *a) nogil
    int GpuArray_split(_GpuArray **rs, const _GpuArray *a, size_t n,
                       size_t *p, unsigned int axis)
    int GpuArray_concatenate(_GpuArray *r, const _GpuArray **as, size_t n,
                             unsigned int axis, int restype)

    char *GpuArray_error(_GpuArray *a, int err)

    void GpuArray_fprintf(libc.stdio.FILE *fd, _GpuArray *a)
    bint GpuArray_is_c_contiguous(_GpuArray *a)
    bint GpuArray_is_f_contiguous(_GpuArray *a)

cdef extern from "gpuarray/extension.h":
    void *gpuarray_get_extension(const char *)
    ctypedef struct GpuArrayIpcMemHandle:
        pass

    cdef int GPUARRAY_CUDA_CTX_NOFREE

cdef type get_exc(int errcode)

cdef np.dtype dtype_to_npdtype(dtype)
# If you change the api interface, you MUST increment either the minor
# (if you add a function) or the major version (if you change
# arguments or remove a function) in the gpuarray.pyx file.
cdef api np.dtype typecode_to_dtype(int typecode)
cdef api int get_typecode(dtype) except -1
cpdef int dtype_to_typecode(dtype) except -1

cdef ga_order to_ga_order(ord) except <ga_order>-2

cdef bint py_CHKFLAGS(GpuArray a, int flags)
cdef bint py_ISONESEGMENT(GpuArray a)

cdef int array_empty(GpuArray a, gpucontext *ctx,
                     int typecode, unsigned int nd, const size_t *dims,
                     ga_order ord) except -1
cdef int array_fromdata(GpuArray a,
                        gpudata *data, size_t offset, int typecode,
                        unsigned int nd, const size_t *dims,
                        const ssize_t *strides, int writeable) except -1
cdef int array_view(GpuArray v, GpuArray a) except -1
cdef int array_sync(GpuArray a) except -1
cdef int array_index(GpuArray r, GpuArray a, const ssize_t *starts,
                     const ssize_t *stops, const ssize_t *steps) except -1
cdef int array_take1(GpuArray r, GpuArray a, GpuArray i,
                     int check_err) except -1
cdef int array_setarray(GpuArray v, GpuArray a) except -1
cdef int array_reshape(GpuArray res, GpuArray a, unsigned int nd,
                       const size_t *newdims, ga_order ord,
                       bint nocopy) except -1
cdef int array_transpose(GpuArray res, GpuArray a,
                         const unsigned int *new_axes) except -1
cdef int array_clear(GpuArray a) except -1
cdef bint array_share(GpuArray a, GpuArray b)
cdef gpucontext *array_context(GpuArray a) except NULL
cdef int array_move(GpuArray a, GpuArray src) except -1
cdef int array_write(GpuArray a, void *src, size_t sz) except -1
cdef int array_read(void *dst, size_t sz, GpuArray src) except -1
cdef int array_memset(GpuArray a, int data) except -1
cdef int array_copy(GpuArray res, GpuArray a, ga_order order) except -1
cdef int array_transfer(GpuArray res, GpuArray a) except -1

cdef const char *kernel_error(GpuKernel k, int err) except NULL
cdef int kernel_init(GpuKernel k, gpucontext *ctx,
                     unsigned int count, const char **strs, const size_t *len,
                     const char *name, unsigned int argcount, const int *types,
                     int flags) except -1
cdef int kernel_clear(GpuKernel k) except -1
cdef gpucontext *kernel_context(GpuKernel k) except NULL
cdef int kernel_sched(GpuKernel k, size_t n, size_t *gs, size_t *ls) except -1
cdef int kernel_call(GpuKernel k, unsigned int n,
                     const size_t *gs, const size_t *ls,
                     size_t shared, void **args) except -1
cdef int kernel_property(GpuKernel k, int prop_id, void *res) except -1

cdef int ctx_property(GpuContext c, int prop_id, void *res) except -1
cdef GpuContext ensure_context(GpuContext c)

cdef api GpuContext pygpu_default_context()

cdef api bint pygpu_GpuArray_Check(object o)

cdef api GpuContext pygpu_init(object dev, gpucontext_props *p)

cdef api GpuArray pygpu_zeros(unsigned int nd, const size_t *dims,
                              int typecode, ga_order order,
                              GpuContext context, object cls)
cdef api GpuArray pygpu_empty(unsigned int nd, const size_t *dims,
                              int typecode, ga_order order,
                              GpuContext context, object cls)
cdef api GpuArray pygpu_fromgpudata(gpudata *buf, size_t offset, int typecode,
                                    unsigned int nd, const size_t *dims,
                                    const ssize_t *strides, GpuContext context,
                                    bint writable, object base, object cls)

cdef api GpuArray pygpu_copy(GpuArray a, ga_order ord)

cdef api int pygpu_move(GpuArray a, GpuArray src) except -1

cdef api GpuArray pygpu_view(GpuArray a, object cls)

cdef api int pygpu_sync(GpuArray a) except -1

cdef api GpuArray pygpu_empty_like(GpuArray a, ga_order ord, int typecode)

cdef api np.ndarray pygpu_as_ndarray(GpuArray a)
cdef np.ndarray _pygpu_as_ndarray(GpuArray a, np.dtype ldtype)

cdef api GpuArray pygpu_index(GpuArray a, const ssize_t *starts,
                              const ssize_t *stops, const ssize_t *steps)

cdef api GpuArray pygpu_reshape(GpuArray a, unsigned int nd,
                                const size_t *newdims, ga_order ord,
                                bint nocopy, int compute_axis)
cdef api GpuArray pygpu_transpose(GpuArray a, const unsigned int *newaxes)

cdef api int pygpu_transfer(GpuArray res, GpuArray a) except -1
cdef api GpuArray pygpu_concatenate(const _GpuArray **a, size_t n,
                                    unsigned int axis, int restype,
                                    object cls, GpuContext context)

cdef api class GpuContext [type PyGpuContextType, object PyGpuContextObject]:
    cdef dict __dict__
    cdef gpucontext* ctx
    cdef readonly bytes kind
    cdef object __weakref__

cdef GpuArray new_GpuArray(object cls, GpuContext ctx, object base)

cdef api class GpuArray [type PyGpuArrayType, object PyGpuArrayObject]:
    cdef _GpuArray ga
    cdef readonly GpuContext context
    cdef readonly object base
    cdef object __weakref__

    cdef __index_helper(self, key, unsigned int i, ssize_t *start,
                        ssize_t *stop, ssize_t *step)
    cdef __cgetitem__(self, idx)

cdef api class GpuKernel [type PyGpuKernelType, object PyGpuKernelObject]:
    cdef _GpuKernel k
    cdef readonly GpuContext context
    cdef void **callbuf
    cdef object __weakref__

    cdef do_call(self, py_n, py_gs, py_ls, py_args, size_t shared)
    cdef _setarg(self, unsigned int index, int typecode, object o)
