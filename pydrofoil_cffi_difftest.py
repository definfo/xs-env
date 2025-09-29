import _pydrofoil
from cffi import FFI

ffibuilder = FFI()

# C definitions for CFFI parsing.
# CFFI's parser understands standard C types like uint64_t, size_t, etc.
# We use '_Bool' for boolean types as CFFI can parse it without needing <stdbool.h>.
c_declarations = """
    typedef uint64_t reg_t;

    typedef struct {
      uint64_t gpr[32];
      uint64_t fpr[32];
      uint64_t priv;
      uint64_t mstatus;
      uint64_t sstatus;
      uint64_t mepc;
      uint64_t sepc;
      uint64_t mtval;
      uint64_t stval;
      uint64_t mtvec;
      uint64_t stvec;
      uint64_t mcause;
      uint64_t scause;
      uint64_t satp;
      uint64_t mip;
      uint64_t mie;
      uint64_t mscratch;
      uint64_t sscratch;
      uint64_t mideleg;
      uint64_t medeleg;
      uint64_t pc;

      uint64_t v;
      uint64_t mtval2;
      uint64_t mtinst;
      uint64_t hstatus;
      uint64_t hideleg;
      uint64_t hedeleg;
      uint64_t hcounteren;
      uint64_t htval;
      uint64_t htinst;
      uint64_t hgatp;
      uint64_t vsstatus;
      uint64_t vstvec;
      uint64_t vsepc;
      uint64_t vscause;
      uint64_t vstval;
      uint64_t vsatp;
      uint64_t vsscratch;

      union {
        uint64_t _64[2];
        uint32_t _32[4];
        uint16_t _16[8];
        uint8_t  _8[16];
      } vr[32];
      uint64_t vstart;
      uint64_t vxsat;
      uint64_t vxrm;
      uint64_t vcsr;
      uint64_t vl;
      uint64_t vtype;
      uint64_t vlenb;

      uint64_t fcsr;

      uint64_t tselect;
      uint64_t tdata1;
      uint64_t tinfo;

      uint64_t debugMode;
      uint64_t dcsr;
      uint64_t dpc;
      uint64_t dscratch0;
      uint64_t dscratch1;
    } diff_context_t;

    typedef struct {
      _Bool ignore_illegal_mem_access;
      _Bool debug_difftest;
    } diff_ref_config;

    typedef struct {
      uint64_t sc_failed;
    } diff_uarch_status;

    typedef struct {
        _Bool platform_irp_meip;
        _Bool platform_irp_mtip;
        _Bool platform_irp_msip;
        _Bool platform_irp_seip;
        _Bool platform_irp_stip;
        _Bool platform_irp_vseip;
        _Bool platform_irp_vstip;
        _Bool lcofi_req;
    } diff_non_reg_int;

    int difftest_disambiguation_state();
    void difftest_memcpy(uint64_t addr, void *buf, size_t n, _Bool direction);
    void difftest_regcpy(diff_context_t* dut, _Bool direction, _Bool on_demand);
    void difftest_csrcpy(void *dut, _Bool direction);
    void difftest_pmpcpy(void *dut, _Bool direction);
    void difftest_pmp_cfg_cpy(void *dut, _Bool direction);
    void difftest_uarchstatus_sync(diff_uarch_status *dut);
    void update_dynamic_config(diff_ref_config *config);
    void difftest_exec(uint64_t n);
    void difftest_skip_one(_Bool isRVC, _Bool wen, uint32_t wdest, uint64_t wdata);
    void difftest_init(int port);
    void difftest_raise_intr(uint64_t NO);
    void difftest_dirty_fsvs(uint64_t dirties);
    _Bool difftest_raise_critical_error();
    void isa_reg_display();
    void difftest_display();
    int difftest_store_commit(uint64_t *addr, uint64_t *data, uint8_t *mask);
    uint64_t difftest_guided_exec(void *);
    void debug_mem_sync(reg_t addr, void* buf, size_t n);
    void difftest_load_flash_v2(const uint8_t *flash_bin, size_t size);
    void difftest_load_flash(const char *flash_bin_file, size_t size);
    void difftest_set_mhartid(int mhartid);
    void difftest_close();
    void difftest_set_ramsize(size_t size);
    void difftest_non_reg_interrupt_pending(diff_non_reg_int *non_reg_interrupt_pending);
"""

# C source for compilation, including necessary headers.
# The C compiler needs the real headers to know about 'bool', 'uint64_t', etc.
c_source = """
    #include <stdbool.h>
    #include <stdint.h>
    #include <stddef.h>
""" + c_declarations.replace("_Bool", "bool")

ffibuilder.embedding_api(c_declarations)

ffibuilder.set_source(
    "difftest_pydrofoil_riscv",
    c_source,
    libraries=['pypy3.11-c'],
)

ffibuilder.embedding_init_code("""
    from difftest_pydrofoil_riscv import ffi
    import _pydrofoil
    from collections import Counter

    cpu = None
    ref_cfg = ffi.new("diff_ref_config *")
    ref_cfg.ignore_illegal_mem_access = False
    ref_cfg.debug_difftest = False

    @ffi.def_extern
    def difftest_disambiguation_state():
        #
        # def clear_ambiguation_state()
        #     smc_tracker.state_reset()
        #     pte_tracker.state_reset()
        #     satp_written = false
        #
        # s = smc_tracker.state() or pte_tracker.state() or satp_written
        # clear_ambiguation_state()
        # return s
        return 0

    @ffi.def_extern
    def difftest_memcpy(addr, buf, n, direction):
        if direction: # True: DIFFTEST -> REF
            cpu.write_memory(addr, buf, n)
        else: # False: REF -> DIFFTEST
            print("difftest_memcpy with REF->DIFFTEST is not supported yet")

    @ffi.def_extern
    def difftest_regcpy(dut, direction, on_demand):
        if direction: # True: DIFFTEST -> REF
            dut_diff_ctx = ffi.cast("diff_context_t *", dut)
            for reg, _ in cpu.register_info():
                # TODO: match register names between Pydrofoil and difftest
                if dut_diff_ctx[reg]:
                    cpu.write_register(reg, dut_diff_ctx[reg])
        else: # False: REF -> DIFFTEST
            pass

    @ffi.def_extern
    def difftest_csrcpy(dut, direction):
        # csr = cpu.lowlevel.write_CSR(dut)
        pass

    @ffi.def_extern
    def difftest_pmpcpy(dut, direction):
        # TODO: implement this
        pass

    @ffi.def_extern
    def difftest_pmp_cfg_cpy(dut, direction):
        pass

    @ffi.def_extern
    def difftest_uarchstatus_sync(dut):
        # TODO: implement this
        pass

    @ffi.def_extern
    def update_dynamic_config(config):
        # TODO: implement this
        global ref_cfg
        ref_cfg = config

    @ffi.def_extern
    def difftest_exec(n):
        for _ in range(int(n)):
            cpu.step()

    @ffi.def_extern
    def difftest_skip_one(isRVC, wen, wdest, wdata):
        # xpr, minstret ?
        pc_addr = cpu.get_register('pc')
        cpu.write_register('pc', pc_addr + 2 if isRVC else pc_addr + 4)

    @ffi.def_extern
    def difftest_init(port):
        global cpu
        # TODO: select & load elf during build phase
        cpu = _pydrofoil.RISCV64("./riscv/input/rv64-linux-4.15.0-gcc-7.2.0-64mb.bbl", dtb=True)
        cpu.set_verbosity(0)

        # record with Counter to dump extra info
        #
        # cnt = Counter()

    @ffi.def_extern
    def difftest_raise_intr(NO):
        # TODO: implement this
        pass

    @ffi.def_extern
    def difftest_dirty_fsvs(dirties):
        # TODO: implement this
        pass

    @ffi.def_extern
    def difftest_raise_critical_error():
        # This simply change state variable on Spike's side
        # Not sure if we should mimic such behaviour...
        return False

    @ffi.def_extern
    def isa_reg_display():
        print(cpu.register_info())

    @ffi.def_extern
    def difftest_display():
        # TODO: Pretty print as simpleprofiler.py
        # cpu.memory_info(), cpu.register_info(), etc.
        pass

    @ffi.def_extern
    def difftest_store_commit(addr, data, mask):
        return 0

    @ffi.def_extern
    def difftest_guided_exec(p):
        cpu.step()
        return 0 # must return an integer

    @ffi.def_extern
    def debug_mem_sync(addr, buf, n):
        # TODO: implement this
        pass

    @ffi.def_extern
    def difftest_load_flash_v2(flash_bin, size):
        # unsupported ?
        pass

    @ffi.def_extern
    def difftest_load_flash(flash_bin_file, size):
        # unsupported ?
        pass

    @ffi.def_extern
    def difftest_set_mhartid(mhartid):
        # TODO: implement this
        pass

    @ffi.def_extern
    def difftest_close():
        exit(0)

    @ffi.def_extern
    def difftest_set_ramsize(size):
        # unsupported ?
        pass

    @ffi.def_extern
    def difftest_non_reg_interrupt_pending(non_reg_interrupt_pending):
        pass
"""
)

ffibuilder.compile(verbose=True)
