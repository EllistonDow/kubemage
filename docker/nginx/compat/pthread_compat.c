#define _XOPEN_SOURCE 700
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <string.h>

#ifndef NSIG
#define NSIG _NSIG
#endif

#ifdef pthread_mutex_consistent_np
#undef pthread_mutex_consistent_np
#endif
int pthread_mutex_consistent_np(pthread_mutex_t *mutex) {
    return pthread_mutex_consistent(mutex);
}

#ifdef pthread_mutexattr_setrobust_np
#undef pthread_mutexattr_setrobust_np
#endif
int pthread_mutexattr_setrobust_np(pthread_mutexattr_t *attr, int robust) {
    return pthread_mutexattr_setrobust(attr, robust);
}

#ifdef pthread_yield
#undef pthread_yield
#endif
int pthread_yield(void) {
    return sched_yield();
}

const char *sys_siglist[NSIG];

__attribute__((constructor)) static void init_sys_siglist(void) {
    for (int i = 0; i < NSIG; ++i) {
        sys_siglist[i] = strsignal(i);
    }
}
