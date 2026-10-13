/* Interpose ownership calls so Alpine packages install in a user namespace
 * that can only represent uid/gid 0. Records intended owners for mksquashfs.
 * Also fakes stat() so package scripts observe the owners they just set.
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/sysmacros.h>
#include <unistd.h>

#ifndef AT_FDCWD
#define AT_FDCWD -100
#endif
#ifndef AT_SYMLINK_NOFOLLOW
#define AT_SYMLINK_NOFOLLOW 0x100
#endif
#ifndef SYS_newfstatat
#define SYS_newfstatat 262
#endif
#ifndef SYS_fchownat
#define SYS_fchownat 260
#endif
#ifndef SYS_renameat
#define SYS_renameat 264
#endif
#ifndef SYS_renameat2
#define SYS_renameat2 316
#endif
#ifndef SYS_mknodat
#define SYS_mknodat 259
#endif
#ifndef SYS_mkdirat
#define SYS_mkdirat 258
#endif
#ifndef SYS_openat
#define SYS_openat 257
#endif
#ifndef SYS_fstat
#define SYS_fstat 5
#endif
#ifndef SYS_unlinkat
#define SYS_unlinkat 263
#endif

static const char *log_path(void) {
	const char *p = getenv("FAKEOWN_LOG");
	return p && *p ? p : "/fakeown.log";
}

struct ent {
	char *path;
	uid_t uid;
	gid_t gid;
	unsigned devmode;
	unsigned major, minor;
	unsigned hash;
	int state; /* 0 empty, 1 used, 2 tombstone */
};

static struct ent *tab;
static size_t cap, count, tombs;
static int loaded;
static int in_hook;

static unsigned hash_str(const char *s) {
	unsigned h = 2166136261u;
	for (; *s; s++) {
		h ^= (unsigned char)*s;
		h *= 16777619u;
	}
	return h ? h : 1u;
}

static void grow(void) {
	size_t ncap = cap ? cap * 2 : 131072;
	struct ent *n = calloc(ncap, sizeof(*n));
	if (!n) abort();
	size_t ncount = 0;
	for (size_t i = 0; i < cap; i++) {
		if (tab[i].state != 1) continue;
		size_t j = tab[i].hash % ncap;
		while (n[j].state == 1) j = (j + 1) % ncap;
		n[j] = tab[i];
		ncount++;
	}
	free(tab);
	tab = n;
	cap = ncap;
	count = ncount;
	tombs = 0;
}

static struct ent *lookup(const char *path, int create) {
	if (!path || !path[0]) return NULL;
	if (!tab || (create && (count + tombs) * 10 > cap * 6)) grow();
	unsigned h = hash_str(path);
	size_t j = h % cap;
	size_t first_tomb = (size_t)-1;
	for (size_t steps = 0; steps < cap; steps++) {
		if (tab[j].state == 0) {
			if (!create) return NULL;
			if (first_tomb != (size_t)-1) {
				j = first_tomb;
				if (tombs) tombs--;
			}
			tab[j].state = 1;
			tab[j].path = strdup(path);
			if (!tab[j].path) abort();
			tab[j].hash = h;
			tab[j].uid = 0;
			tab[j].gid = 0;
			tab[j].devmode = 0;
			count++;
			return &tab[j];
		}
		if (tab[j].state == 2) {
			if (first_tomb == (size_t)-1) first_tomb = j;
		} else if (tab[j].hash == h && strcmp(tab[j].path, path) == 0) {
			return &tab[j];
		}
		j = (j + 1) % cap;
	}
	if (!create) return NULL;
	grow();
	return lookup(path, 1);
}

static void drop_ent(struct ent *e) {
	free(e->path);
	e->path = NULL;
	e->state = 2;
	if (count) count--;
	tombs++;
}

static void load_log(void) {
	if (loaded) return;
	loaded = 1;
	FILE *f = fopen(log_path(), "r");
	if (!f) return;
	char *line = NULL;
	size_t n = 0;
	while (getline(&line, &n, f) != -1) {
		char kind = line[0];
		if (kind == 'C' || kind == 'D') {
			char path[PATH_MAX];
			unsigned uid = 0, gid = 0, mode = 0, maj = 0, min = 0;
			if (kind == 'C') {
				if (sscanf(line, "C\t%4095[^\t]\t%u\t%u", path, &uid, &gid) == 3) {
					struct ent *e = lookup(path, 1);
					e->uid = uid;
					e->gid = gid;
				}
			} else if (sscanf(line, "D\t%4095[^\t]\t%u\t%u\t%u\t%u\t%u",
					  path, &mode, &maj, &min, &uid, &gid) == 6) {
				struct ent *e = lookup(path, 1);
				e->uid = uid;
				e->gid = gid;
				e->devmode = mode;
				e->major = maj;
				e->minor = min;
			}
		} else if (kind == 'R') {
			char a[PATH_MAX], b[PATH_MAX];
			if (sscanf(line, "R\t%4095[^\t]\t%4095[^\n]", a, b) == 2) {
				struct ent *e = lookup(a, 0);
				if (e) {
					uid_t uid = e->uid;
					gid_t gid = e->gid;
					unsigned devmode = e->devmode, major = e->major, minor = e->minor;
					drop_ent(e);
					struct ent *n = lookup(b, 1);
					n->uid = uid;
					n->gid = gid;
					n->devmode = devmode;
					n->major = major;
					n->minor = minor;
				}
			}
		}
	}
	free(line);
	fclose(f);
}

static void append_log(const char *fmt, ...) {
	int fd = syscall(SYS_openat, AT_FDCWD, log_path(),
			 O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
	if (fd < 0) return;
	char buf[PATH_MAX + 128];
	va_list ap;
	va_start(ap, fmt);
	int len = vsnprintf(buf, sizeof buf, fmt, ap);
	va_end(ap);
	if (len > 0) {
		size_t off = 0;
		if (len > (int)sizeof buf) len = (int)sizeof buf;
		while (off < (size_t)len) {
			long w = syscall(SYS_write, fd, buf + off, (size_t)len - off);
			if (w < 0) break;
			off += (size_t)w;
		}
	}
	syscall(SYS_close, fd);
}

/* write() via syscall number if SYS_write missing include */
#ifndef SYS_write
#define SYS_write 1
#endif
#ifndef SYS_close
#define SYS_close 3
#endif

static int resolve_path(int dirfd, const char *path, char *out, size_t outsz) {
	if (!path) return -1;
	if (path[0] == '/') {
		snprintf(out, outsz, "%s", path);
		return 0;
	}
	char dir[PATH_MAX];
	if (dirfd == AT_FDCWD) {
		if (!getcwd(dir, sizeof dir)) return -1;
	} else {
		char link[64];
		snprintf(link, sizeof link, "/proc/self/fd/%d", dirfd);
		ssize_t n = readlink(link, dir, sizeof dir - 1);
		if (n < 0) {
			snprintf(out, outsz, "%s", path);
			return 0;
		}
		dir[n] = 0;
	}
	if (strcmp(dir, "/") == 0) snprintf(out, outsz, "/%s", path);
	else snprintf(out, outsz, "%s/%s", dir, path);
	return 0;
}

static void apply_owner(const char *path, struct stat *st) {
	if (!path || path[0] != '/') return;
	if (strncmp(path, "/proc", 5) == 0) return;
	if (strncmp(path, "/sys", 4) == 0) return;
	if (strncmp(path, "/dev", 4) == 0) return;
	load_log();
	struct ent *e = lookup(path, 0);
	if (!e) return;
	st->st_uid = e->uid;
	st->st_gid = e->gid;
}

static void note_chown(int dirfd, const char *path, uid_t uid, gid_t gid) {
	char full[PATH_MAX];
	if (resolve_path(dirfd, path, full, sizeof full) != 0) return;
	if (strcmp(full, log_path()) == 0) return;
	load_log();
	struct ent *e = lookup(full, 1);
	e->uid = uid;
	e->gid = gid;
	append_log("C\t%s\t%u\t%u\n", full, (unsigned)uid, (unsigned)gid);
}

int fchownat(int dirfd, const char *pathname, uid_t owner, gid_t group, int flags) {
	note_chown(dirfd, pathname, owner, group);
	if (owner == 0 && group == 0)
		return syscall(SYS_fchownat, dirfd, pathname, owner, group, flags);
	return 0;
}

int chown(const char *pathname, uid_t owner, gid_t group) {
	return fchownat(AT_FDCWD, pathname, owner, group, 0);
}

int lchown(const char *pathname, uid_t owner, gid_t group) {
	return fchownat(AT_FDCWD, pathname, owner, group, AT_SYMLINK_NOFOLLOW);
}

int fchown(int fd, uid_t owner, gid_t group) {
	char link[64], path[PATH_MAX];
	snprintf(link, sizeof link, "/proc/self/fd/%d", fd);
	ssize_t n = readlink(link, path, sizeof path - 1);
	if (n > 0) {
		path[n] = 0;
		note_chown(AT_FDCWD, path, owner, group);
	}
	if (owner == 0 && group == 0) return syscall(SYS_fchown, fd, owner, group);
	return 0;
}

#ifndef SYS_fchown
#define SYS_fchown 93
#endif

static void note_rename(int olddirfd, const char *oldpath, int newdirfd, const char *newpath) {
	char a[PATH_MAX], b[PATH_MAX];
	if (resolve_path(olddirfd, oldpath, a, sizeof a) != 0) return;
	if (resolve_path(newdirfd, newpath, b, sizeof b) != 0) return;
	load_log();
	struct ent *e = lookup(a, 0);
	if (!e) return;
	uid_t uid = e->uid;
	gid_t gid = e->gid;
	unsigned devmode = e->devmode, major = e->major, minor = e->minor;
	drop_ent(e);
	struct ent *n = lookup(b, 1);
	n->uid = uid;
	n->gid = gid;
	n->devmode = devmode;
	n->major = major;
	n->minor = minor;
	append_log("R\t%s\t%s\n", a, b);
}

int renameat(int olddirfd, const char *oldpath, int newdirfd, const char *newpath) {
	int r = syscall(SYS_renameat, olddirfd, oldpath, newdirfd, newpath);
	if (r == 0) note_rename(olddirfd, oldpath, newdirfd, newpath);
	return r;
}

int renameat2(int olddirfd, const char *oldpath, int newdirfd, const char *newpath, unsigned int flags) {
	int r = syscall(SYS_renameat2, olddirfd, oldpath, newdirfd, newpath, flags);
	if (r == 0) note_rename(olddirfd, oldpath, newdirfd, newpath);
	return r;
}

int rename(const char *oldpath, const char *newpath) {
	return renameat(AT_FDCWD, oldpath, AT_FDCWD, newpath);
}

static int fake_mknod(int dirfd, const char *pathname, mode_t mode, dev_t dev) {
	char full[PATH_MAX];
	if (resolve_path(dirfd, pathname, full, sizeof full) != 0) return 0;
	unsigned maj = major(dev), min = minor(dev);
	load_log();
	struct ent *e = lookup(full, 1);
	e->devmode = mode;
	e->major = maj;
	e->minor = min;
	append_log("D\t%s\t%u\t%u\t%u\t%u\t%u\n", full, (unsigned)mode, maj, min,
		   (unsigned)e->uid, (unsigned)e->gid);
	/* placeholder so later rename/chmod/open succeed */
	int fd = syscall(SYS_openat, dirfd, pathname, O_CREAT | O_WRONLY | O_EXCL | O_CLOEXEC, 0644);
	if (fd >= 0) syscall(SYS_close, fd);
	else if (errno != EEXIST) {
		/* directory component missing or other: still pretend success */
	}
	return 0;
}

int mknodat(int dirfd, const char *pathname, mode_t mode, dev_t dev) {
	if (S_ISCHR(mode) || S_ISBLK(mode) || S_ISFIFO(mode))
		return fake_mknod(dirfd, pathname, mode, dev);
	return syscall(SYS_mknodat, dirfd, pathname, mode, dev);
}

int mknod(const char *pathname, mode_t mode, dev_t dev) {
	return mknodat(AT_FDCWD, pathname, mode, dev);
}

int stat(const char *pathname, struct stat *st) {
	if (in_hook) return syscall(SYS_newfstatat, AT_FDCWD, pathname, st, 0);
	in_hook = 1;
	int r = syscall(SYS_newfstatat, AT_FDCWD, pathname, st, 0);
	if (r == 0 && pathname) {
		char full[PATH_MAX];
		if (pathname[0] == '/') apply_owner(pathname, st);
		else if (resolve_path(AT_FDCWD, pathname, full, sizeof full) == 0)
			apply_owner(full, st);
	}
	in_hook = 0;
	return r;
}

int lstat(const char *pathname, struct stat *st) {
	if (in_hook) return syscall(SYS_newfstatat, AT_FDCWD, pathname, st, AT_SYMLINK_NOFOLLOW);
	in_hook = 1;
	int r = syscall(SYS_newfstatat, AT_FDCWD, pathname, st, AT_SYMLINK_NOFOLLOW);
	if (r == 0 && pathname) {
		char full[PATH_MAX];
		if (pathname[0] == '/') apply_owner(pathname, st);
		else if (resolve_path(AT_FDCWD, pathname, full, sizeof full) == 0)
			apply_owner(full, st);
	}
	in_hook = 0;
	return r;
}

int fstat(int fd, struct stat *st) {
	int r = syscall(SYS_fstat, fd, st);
	if (r == 0 && !in_hook) {
		in_hook = 1;
		char link[64], path[PATH_MAX];
		snprintf(link, sizeof link, "/proc/self/fd/%d", fd);
		ssize_t n = readlink(link, path, sizeof path - 1);
		if (n > 0) {
			path[n] = 0;
			apply_owner(path, st);
		}
		in_hook = 0;
	}
	return r;
}

int fstatat(int dirfd, const char *pathname, struct stat *st, int flags) {
	if (in_hook) return syscall(SYS_newfstatat, dirfd, pathname, st, flags);
	in_hook = 1;
	int r = syscall(SYS_newfstatat, dirfd, pathname, st, flags);
	if (r == 0 && pathname) {
		char full[PATH_MAX];
		if (resolve_path(dirfd, pathname, full, sizeof full) == 0)
			apply_owner(full, st);
	}
	in_hook = 0;
	return r;
}

/* musl sometimes exports this name */
int __fstatat(int dirfd, const char *pathname, struct stat *st, int flags) {
	return fstatat(dirfd, pathname, st, flags);
}
