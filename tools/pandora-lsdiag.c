/*
 * data-a-live songyuan: LaunchServices / PosterBoard diagnostic and repair, as a native binary
 * (the port's root file system has no shell). Installed as /usr/libexec/datamigrator so launchd
 * runs it at boot instead of the (unused) migration job.
 *
 * It appends markers to /var/mobile/Library/Logs/pandora-ls.txt and writes the tool output to
 *   /var/mobile/Library/Logs/lsreg-before.txt
 *   /var/mobile/Library/Logs/lsreg-after.txt
 *   /var/mobile/Library/Logs/lsdiag-before.txt
 *   /var/mobile/Library/Logs/lsdiag-after.txt
 *   /var/mobile/Library/Logs/appex.txt
 * all of which the kernel file dumper can read on the next boot (boot-arg pandora_dumpfile).
 */
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <spawn.h>`n#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

#define LOGDIR "/var/mobile/Library/Logs"
#define MARK   LOGDIR "/pandora-ls.txt"

static FILE *mark;

static void
msg(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	if (mark) {
		vfprintf(mark, fmt, ap);
		fputc('\n', mark);
		fflush(mark);
	}
	va_end(ap);
}

/* Run argv[0] with stderr+stdout appended to outpath. Returns exit code or -1. */
static int
run_to_file(char *const argv[], const char *outpath)
{
	posix_spawn_file_actions_t fa;
	pid_t pid;
	int fd, status, rc;

	posix_spawn_file_actions_init(&fa);
	posix_spawn_file_actions_addopen(&fa, 1, outpath, O_WRONLY | O_CREAT | O_APPEND, 0644);
	posix_spawn_file_actions_addopen(&fa, 2, outpath, O_WRONLY | O_CREAT | O_APPEND, 0644);
	rc = posix_spawn(&pid, argv[0], &fa, NULL, argv, environ);
	posix_spawn_file_actions_destroy(&fa);
	if (rc != 0) {
		return -rc;
	}
	if (waitpid(pid, &status, 0) < 0) {
		return -1;
	}
	if (WIFEXITED(status)) {
		return WEXITSTATUS(status);
	}
	return -2;
}

static void
list_dir(const char *path)
{
	DIR *d = opendir(path);
	struct dirent *de;
	if (d == NULL) {
		msg("## %s: open: %d", path, errno);
		return;
	}
	msg("## %s:", path);
	while ((de = readdir(d)) != NULL) {
		msg("   %s", de->d_name);
	}
	closedir(d);
}

/* Recursively log *.appex bundles under path, at most maxdepth levels, at most 200 lines. */
static int appex_lines;
static void
find_appex(const char *path, int depth, int maxdepth)
{
	DIR *d;
	struct dirent *de;
	char buf[1024];
	if (depth > maxdepth || appex_lines >= 200) {
		return;
	}
	d = opendir(path);
	if (d == NULL) {
		return;
	}
	while ((de = readdir(d)) != NULL) {
		size_t n;
		if (de->d_name[0] == '.' && (de->d_name[1] == 0 ||
		    (de->d_name[1] == '.' && de->d_name[2] == 0))) {
			continue;
		}
		n = strlen(de->d_name);
		if (n > 4 && strcmp(de->d_name + n - 5, ".appex") == 0) {
			msg("APPEX %s/%s", path, de->d_name);
			appex_lines++;
			continue;
		}
		if (snprintf(buf, sizeof(buf), "%s/%s", path, de->d_name) < (int)sizeof(buf)) {
			find_appex(buf, depth + 1, maxdepth);
		}
	}
	closedir(d);
}

int
main(void)
{
	static char *const lsreg_candidates[] = {
		"/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
		"/System/Library/PrivateFrameworks/LaunchServices.framework/Support/lsregister",
		NULL,
	};
	const char *lsreg = NULL;
	char logpath[256];
	int i, rc;

	mkdir(LOGDIR, 0755);
	mark = fopen(MARK, "a");
	if (mark == NULL) {
		return 1;
	}
	msg("=== PANDORA LS REPAIR start");
	for (i = 0; lsreg_candidates[i]; i++) {
		if (access(lsreg_candidates[i], X_OK) == 0) {
			lsreg = lsreg_candidates[i];
			break;
		}
	}
	msg("lsregister: %s", lsreg ? lsreg : "(not found)");

	/* baseline listings */
	list_dir("/bin");
	list_dir("/usr/bin");
	list_dir("/System/Library/ExtensionKit");
	list_dir("/System/Library/ExtensionKit/Extensions");
	list_dir("/System/Library/PrivateFrameworks/PosterBoard.framework");
	list_dir("/System/Library/PrivateFrameworks/PosterBoard.framework/PlugIns");
	list_dir("/System/Library/PrivateFrameworks/PosterKit.framework");
	list_dir("/System/Library/PrivateFrameworks/WallpaperKit.framework");
	list_dir("/Library/Wallpaper");
	find_appex("/System/Library/PrivateFrameworks", 0, 2);
	find_appex("/System/Library/ExtensionKit", 0, 3);
	find_appex("/Applications", 0, 3);
	msg("appex total: %d", appex_lines);

	/* before */
	if (lsreg) {
		char *const a1[] = {(char *)lsreg, "-dump", NULL};
		rc = run_to_file(a1, LOGDIR "/lsreg-before.txt");
		msg("lsregister -dump before: %d", rc);
	}
	{
		char *const ad[] = {"/usr/bin/lsdiagnose", NULL};
		rc = run_to_file(ad, LOGDIR "/lsdiag-before.txt");
		msg("lsdiagnose before: %d", rc);
	}

	/* repair */
	if (lsreg) {
		char *const a2[] = {(char *)lsreg, "-kill", "-r", "-domain", "local",
		    "-domain", "system", "-domain", "user", NULL};
		rc = run_to_file(a2, MARK);
		msg("lsregister -kill -r: %d", rc);
	}
	sleep(15);
	{
		char *const ad[] = {"/usr/bin/lsdiagnose", NULL};
		rc = run_to_file(ad, LOGDIR "/lsdiag-after.txt");
		msg("lsdiagnose after: %d", rc);
	}
	if (lsreg) {
		char *const a3[] = {(char *)lsreg, "-dump", NULL};
		rc = run_to_file(a3, LOGDIR "/lsreg-after.txt");
		msg("lsregister -dump after: %d", rc);
	}
	msg("=== PANDORA LS REPAIR end");
	fclose(mark);
	return 0;
}
