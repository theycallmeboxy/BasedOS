/*
 * BasedOS: hold Volume Up and Volume Down together for 3 s for BasedOS's own clean shutdown,
 * whatever the frontend is doing (rcK: every process asked to quit, 3 s to save, then killed;
 * sync; the card unmounted or remounted read-only). The way out of a hung frontend short of the
 * PMIC's power cut. Holding power is left to the frontend.
 *
 * It asks the keys' state (EVIOCGKEY) instead of reading their events: a frontend may grab an
 * input device for itself (spruce grabs the power key so RetroArch never sees it), and a grab
 * hides the events from every other reader, but not the state. The keys are found by what each
 * device reports (EVIOCGBIT), not by its name. Once a second while the combo isn't held, every
 * 0.2 s while it is. Monotonic time stops in suspend. Started by rcS in the background.
 */
#include <dirent.h>
#include <fcntl.h>
#include <linux/input.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define HOLD_MS 3000
#define NBYTES (KEY_MAX / 8 + 1)

static const int keys[] = { KEY_VOLUMEUP, KEY_VOLUMEDOWN };
#define NKEYS (int)(sizeof(keys) / sizeof(keys[0]))
static int fds[NKEYS];

static int bit(const unsigned char *b, int code)
{
	return b[code / 8] & (1 << (code % 8));
}

/* A BasedOS shell helper (log, say) with one argument. */
static void sh(const char *helper, const char *msg)
{
	char cmd[64];
	pid_t pid;

	snprintf(cmd, sizeof(cmd), ". /usr/lib/basedos/functions; %s \"$1\"", helper);
	pid = fork();
	if (pid == 0) {
		execl("/bin/sh", "sh", "-c", cmd, "basedos-shutdown-keys", msg, (char *)NULL);
		_exit(127);
	}
	if (pid > 0)
		waitpid(pid, NULL, 0);
}

static long now_ms(void)
{
	struct timespec t;

	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec * 1000L + t.tv_nsec / 1000000L;
}

/* For each key, the first input device that has it. */
static int open_keys(void)
{
	DIR *d = opendir("/dev/input");
	struct dirent *e;
	int found = 0;

	for (int k = 0; k < NKEYS; k++)
		fds[k] = -1;
	if (!d)
		return 0;
	while ((e = readdir(d)) && found < NKEYS) {
		unsigned char caps[NBYTES] = { 0 };
		char path[300];
		int fd, used = 0;

		if (strncmp(e->d_name, "event", 5))
			continue;
		snprintf(path, sizeof(path), "/dev/input/%s", e->d_name);
		fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
		if (fd < 0)
			continue;
		if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(caps)), caps) >= 0)
			for (int k = 0; k < NKEYS; k++)
				if (fds[k] < 0 && bit(caps, keys[k])) {
					fds[k] = fd;
					used = 1;
					found++;
				}
		if (!used)
			close(fd);
	}
	closedir(d);
	return found == NKEYS;
}

/* Both held right now; -1 if a device stopped answering. */
static int held(void)
{
	for (int k = 0; k < NKEYS; k++) {
		unsigned char state[NBYTES] = { 0 };

		if (ioctl(fds[k], EVIOCGKEY(sizeof(state)), state) < 0)
			return -1;
		if (!bit(state, keys[k]))
			return 0;
	}
	return 1;
}

static void close_keys(void)
{
	for (int k = 0; k < NKEYS; k++)
		if (fds[k] >= 0) {
			for (int j = k + 1; j < NKEYS; j++)
				if (fds[j] == fds[k])
					fds[j] = -1;
			close(fds[k]);
			fds[k] = -1;
		}
}

int main(void)
{
	char msg[128];

	if (!open_keys()) {
		sh("log", "no volume keys; the shutdown combo is off");
		return 0;
	}
	snprintf(msg, sizeof(msg), "watching the volume keys (hold both %d s to shut down)", HOLD_MS / 1000);
	sh("log", msg);
	for (;;) {
		long start;
		int h = held();

		if (h < 0) {
			/* Never leave the session without the way out: find the keys again. */
			sh("log", "lost the volume keys; looking again");
			close_keys();
			sleep(1);
			if (!open_keys()) {
				sh("log", "no volume keys; the shutdown combo is off");
				return 0;
			}
			continue;
		}
		if (!h) {
			sleep(1);
			continue;
		}
		start = now_ms();
		while ((h = held()) == 1) {
			if (now_ms() - start >= HOLD_MS) {
				snprintf(msg, sizeof(msg), "volume up + down held %d s: shutting down", HOLD_MS / 1000);
				sh("say", msg);
				execl("/sbin/poweroff", "poweroff", (char *)NULL);
				return 1;
			}
			usleep(200000);
		}
	}
}
