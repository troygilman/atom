/* OpenShell returns EPERM for uid/gid syscalls even when the ids do not
 * change. Xorg's Popen (used by Xvfb to run xkbcomp) and xterm both treat
 * that as fatal. Ignore the error only when every requested id is already
 * current or is the usual "leave unchanged" value of -1.
 *
 * A real uid or gid change still returns the error.
 * See docs/spike-notes.md.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <unistd.h>
#include <sys/types.h>

static int same_or_unset(uid_t requested, uid_t current)
{
    return requested == (uid_t)-1 || requested == current;
}

int setuid(uid_t uid)
{
    static int (*real_setuid)(uid_t) = 0;
    if (!real_setuid)
        real_setuid = dlsym(RTLD_NEXT, "setuid");
    int rc = real_setuid(uid);
    if (rc < 0 && uid == getuid())
        return 0;
    return rc;
}

int setgid(gid_t gid)
{
    static int (*real_setgid)(gid_t) = 0;
    if (!real_setgid)
        real_setgid = dlsym(RTLD_NEXT, "setgid");
    int rc = real_setgid(gid);
    if (rc < 0 && gid == getgid())
        return 0;
    return rc;
}

int seteuid(uid_t uid)
{
    static int (*real_seteuid)(uid_t) = 0;
    if (!real_seteuid)
        real_seteuid = dlsym(RTLD_NEXT, "seteuid");
    int rc = real_seteuid(uid);
    if (rc < 0 && uid == geteuid())
        return 0;
    return rc;
}

int setegid(gid_t gid)
{
    static int (*real_setegid)(gid_t) = 0;
    if (!real_setegid)
        real_setegid = dlsym(RTLD_NEXT, "setegid");
    int rc = real_setegid(gid);
    if (rc < 0 && gid == getegid())
        return 0;
    return rc;
}

int setresuid(uid_t ruid, uid_t euid, uid_t suid)
{
    static int (*real_setresuid)(uid_t, uid_t, uid_t) = 0;
    if (!real_setresuid)
        real_setresuid = dlsym(RTLD_NEXT, "setresuid");
    int rc = real_setresuid(ruid, euid, suid);
    if (rc < 0 && same_or_unset(ruid, getuid()) &&
        same_or_unset(euid, geteuid()) && same_or_unset(suid, geteuid()))
        return 0;
    return rc;
}

int setresgid(gid_t rgid, gid_t egid, gid_t sgid)
{
    static int (*real_setresgid)(gid_t, gid_t, gid_t) = 0;
    if (!real_setresgid)
        real_setresgid = dlsym(RTLD_NEXT, "setresgid");
    int rc = real_setresgid(rgid, egid, sgid);
    if (rc < 0 && same_or_unset(rgid, getgid()) &&
        same_or_unset(egid, getegid()) && same_or_unset(sgid, getegid()))
        return 0;
    return rc;
}
