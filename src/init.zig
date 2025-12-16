pub fn init() align(4096) linksection(".usermode") noreturn {
    while (true) {
        asm volatile ("ecall");
    }
}
