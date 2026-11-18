/*
 * Mainline experiment: dump physical register blocks to files with 32-bit reads through an
 * mmap of /dev/mem (on arm64, read() on /dev/mem only reaches RAM). The probe initrd's
 * counterpart of regdump.py on the stock kernel. Built static by mkcard.py.
 *
 *   regdump <out dir> <name>:<base>:<length> ...
 */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	long page = sysconf(_SC_PAGESIZE);
	int fd, i, rc = 0;

	if (argc < 3) {
		fprintf(stderr, "usage: regdump <out dir> <name>:<base>:<length> ...\n");
		return 2;
	}
	fd = open("/dev/mem", O_RDONLY | O_SYNC);
	if (fd < 0) {
		perror("/dev/mem");
		return 1;
	}
	for (i = 2; i < argc; i++) {
		char name[64], path[512];
		unsigned long base, len, start, off;
		volatile uint32_t *w;
		uint32_t *buf;
		void *m;
		FILE *f;
		size_t n;

		if (sscanf(argv[i], "%63[^:]:%lx:%lx", name, &base, &len) != 3 || len % 4) {
			fprintf(stderr, "bad block %s\n", argv[i]);
			rc = 1;
			continue;
		}
		start = base & ~(page - 1);
		off = base - start;
		m = mmap(NULL, off + len, PROT_READ, MAP_SHARED, fd, start);
		if (m == MAP_FAILED) {
			perror(name);
			rc = 1;
			continue;
		}
		w = (volatile uint32_t *)((char *)m + off);
		buf = malloc(len);
		for (n = 0; n < len / 4; n++)
			buf[n] = w[n];
		munmap(m, off + len);
		snprintf(path, sizeof(path), "%s/%s.bin", argv[1], name);
		f = fopen(path, "wb");
		if (!f || fwrite(buf, 4, len / 4, f) != len / 4) {
			perror(path);
			rc = 1;
		}
		if (f)
			fclose(f);
		free(buf);
	}
	close(fd);
	return rc;
}
