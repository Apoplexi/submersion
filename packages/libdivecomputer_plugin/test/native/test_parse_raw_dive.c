#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "libdc_wrapper.h"

/* Load a binary file into a malloc'd buffer. On success returns the byte count
   and sets *out to the malloc'd buffer (caller frees). On any failure returns 0
   and sets *out to NULL, so the caller can safely free/assert without touching
   an uninitialized or partially-filled buffer. */
static unsigned int load_fixture(const char *path, unsigned char **out) {
    *out = NULL;
    FILE *f = fopen(path, "rb");
    if (!f) return 0;
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (len <= 0) { fclose(f); return 0; }
    unsigned char *buf = (unsigned char *)malloc((size_t)len);
    if (!buf) { fclose(f); return 0; }
    size_t read = fread(buf, 1, (size_t)len, f);
    fclose(f);
    if (read != (size_t)len) { free(buf); return 0; }
    *out = buf;
    return (unsigned int)read;
}

/* Error path: NULL arguments should return INVALIDARGS. */
static void test_null_args(void) {
    libdc_parsed_dive_t result;
    char err[256] = {0};

    int rc = libdc_parse_raw_dive(NULL, "Leonardo", 1, (const unsigned char *)"x", 1, &result, err, sizeof(err));
    assert(rc != 0);

    rc = libdc_parse_raw_dive("Cressi", "Leonardo", 1, NULL, 0, &result, err, sizeof(err));
    assert(rc != 0);

    rc = libdc_parse_raw_dive("Cressi", "Leonardo", 1, (const unsigned char *)"x", 1, NULL, err, sizeof(err));
    assert(rc != 0);

    printf("PASS: test_null_args\n");
}

/* Error path: a missing fixture must report failure and null the out pointer. */
static void test_load_fixture_missing(void) {
    unsigned char *data = (unsigned char *)0x1; /* poison: must be overwritten */
    unsigned int size = load_fixture("fixtures/does_not_exist.bin", &data);
    assert(size == 0);
    assert(data == NULL);
    printf("PASS: test_load_fixture_missing\n");
}

/* Error path: unknown descriptor should return NODEVICE. */
static void test_unknown_descriptor(void) {
    libdc_parsed_dive_t result;
    char err[256] = {0};
    unsigned char dummy[16] = {0};

    int rc = libdc_parse_raw_dive("BogusVendor", "BogusProduct", 9999, dummy, sizeof(dummy), &result, err, sizeof(err));
    assert(rc != 0);
    assert(strlen(err) > 0);
    printf("PASS: test_unknown_descriptor (error: %s)\n", err);
}

/* Happy path: parse real Cressi Leonardo dive data from fixture. */
static void test_parse_cressi_leonardo(void) {
    unsigned char *data = NULL;
    unsigned int size = load_fixture("fixtures/dive1_raw.bin", &data);
    assert(size == 400);
    assert(data != NULL);

    libdc_parsed_dive_t result;
    char err[256] = {0};

    int rc = libdc_parse_raw_dive("Cressi", "Leonardo", 1, data, size, &result, err, sizeof(err));
    if (rc != 0) {
        fprintf(stderr, "FAIL: parse returned %d: %s\n", rc, err);
        free(data);
        assert(0 && "libdc_parse_raw_dive failed");
    }

    /* Basic sanity checks on parsed output. */
    assert(result.max_depth > 0.0);
    assert(result.duration > 0);
    assert(result.sample_count > 0);
    assert(result.samples != NULL);

    /* Verify samples are time-ordered and depths are non-negative. */
    for (unsigned int i = 0; i < result.sample_count; i++) {
        assert(result.samples[i].depth >= 0.0);
        if (i > 0) {
            assert(result.samples[i].time_ms >= result.samples[i - 1].time_ms);
        }
    }

    printf("PASS: test_parse_cressi_leonardo (depth=%.1fm, duration=%us, samples=%u)\n",
           result.max_depth, result.duration, result.sample_count);

    free(result.samples);
    free(result.events);
    free(data);
}

/* --- Ratio iX3M synthetic dive (issue #926) ------------------------------
   The iX3M/iDive family does not implement DC_FIELD_LOCATION. It reports GPS
   as DC_SAMPLE_LOCATION entries inside the profile stream: an "info" record
   (type 1) carries a fix, which libdivecomputer attaches to the next real
   sample record (type 0). This builds the smallest blob that exercises that
   path so the wrapper's entry/exit extraction can be asserted without a
   device. Layout constants mirror divesystem_idive_parser.c. */

#define IX3M_HEADER_SIZE 0x36
#define IX3M_APOS4_SAMPLE_SIZE 0x40
#define IX3M_REC_SAMPLE 0
#define IX3M_REC_INFO 1
/* iX3M 2 GPS Pro. */
#define IX3M2_GPS_PRO_MODEL 0x92

static void put_u16le(unsigned char *p, unsigned int v) {
    p[0] = (unsigned char)(v & 0xFF);
    p[1] = (unsigned char)((v >> 8) & 0xFF);
}

static void put_u32le(unsigned char *p, unsigned int v) {
    p[0] = (unsigned char)(v & 0xFF);
    p[1] = (unsigned char)((v >> 8) & 0xFF);
    p[2] = (unsigned char)((v >> 16) & 0xFF);
    p[3] = (unsigned char)((v >> 24) & 0xFF);
}

/* Write a profile record of the given type at record index `idx`. */
static unsigned char *ix3m_record(unsigned char *blob, unsigned int idx) {
    return blob + IX3M_HEADER_SIZE + idx * IX3M_APOS4_SAMPLE_SIZE;
}

static void ix3m_put_sample(unsigned char *blob, unsigned int idx,
                            unsigned int time_s, unsigned int depth_dm) {
    unsigned char *rec = ix3m_record(blob, idx);
    put_u32le(rec + 2, time_s);
    put_u16le(rec + 6, depth_dm);
    put_u16le(rec + 52, IX3M_REC_SAMPLE);
}

static void ix3m_put_info(unsigned char *blob, unsigned int idx,
                          int latitude_e7, int longitude_e7) {
    unsigned char *rec = ix3m_record(blob, idx);
    put_u32le(rec + 40, 0);  /* altitude (mm) */
    put_u32le(rec + 44, (unsigned int)longitude_e7);
    put_u32le(rec + 48, (unsigned int)latitude_e7);
    put_u16le(rec + 52, IX3M_REC_INFO);
}

/* Regression test for issue #926: GPS fixes from a Ratio iX3M arrive as
   profile samples, not as DC_FIELD_LOCATION. The first fix must land in the
   entry position and the last in the exit position. */
static void test_parse_ratio_ix3m_sample_gps(void) {
    /* Malta: entry ~36.0400 / 14.3200, exit ~36.0450 / 14.3250. */
    const int entry_lat_e7 = 360400000;
    const int entry_lon_e7 = 143200000;
    const int exit_lat_e7 = 360450000;
    const int exit_lon_e7 = 143250000;

    const unsigned int nrecords = 5;
    const unsigned int size = IX3M_HEADER_SIZE + nrecords * IX3M_APOS4_SAMPLE_SIZE;
    unsigned char *blob = (unsigned char *)calloc(1, size);
    assert(blob != NULL);

    put_u16le(blob + 1, nrecords);
    /* Firmware >= 4.x selects the APOS4 sample size and the timezone-aware
       datetime path; byte 48 is the timezone index and must stay even. */
    put_u32le(blob + 0x2A, 40000000);

    ix3m_put_info(blob, 0, entry_lat_e7, entry_lon_e7);
    ix3m_put_sample(blob, 1, 0, 50);
    ix3m_put_sample(blob, 2, 10, 120);
    ix3m_put_info(blob, 3, exit_lat_e7, exit_lon_e7);
    ix3m_put_sample(blob, 4, 20, 30);

    libdc_parsed_dive_t result;
    char err[256] = {0};

    int rc = libdc_parse_raw_dive("Ratio", "iX3M 2 GPS Pro", IX3M2_GPS_PRO_MODEL,
                                  blob, size, &result, err, sizeof(err));
    if (rc != 0) {
        fprintf(stderr, "FAIL: parse returned %d: %s\n", rc, err);
        free(blob);
        assert(0 && "libdc_parse_raw_dive failed for Ratio iX3M");
    }

    assert(result.sample_count == 3);

    assert(!isnan(result.entry_latitude));
    assert(!isnan(result.entry_longitude));
    assert(fabs(result.entry_latitude - 36.04) < 1e-7);
    assert(fabs(result.entry_longitude - 14.32) < 1e-7);

    assert(!isnan(result.exit_latitude));
    assert(!isnan(result.exit_longitude));
    assert(fabs(result.exit_latitude - 36.045) < 1e-7);
    assert(fabs(result.exit_longitude - 14.325) < 1e-7);

    printf("PASS: test_parse_ratio_ix3m_sample_gps (entry=%.5f,%.5f exit=%.5f,%.5f)\n",
           result.entry_latitude, result.entry_longitude,
           result.exit_latitude, result.exit_longitude);

    free(result.samples);
    free(result.events);
    free(blob);
}

/* A single GPS fix must populate the entry position only. Mirroring it into
   the exit position would render a spurious "exit point" on the map. */
static void test_parse_ratio_ix3m_single_fix(void) {
    const unsigned int nrecords = 3;
    const unsigned int size = IX3M_HEADER_SIZE + nrecords * IX3M_APOS4_SAMPLE_SIZE;
    unsigned char *blob = (unsigned char *)calloc(1, size);
    assert(blob != NULL);

    put_u16le(blob + 1, nrecords);
    put_u32le(blob + 0x2A, 40000000);

    ix3m_put_info(blob, 0, 360400000, 143200000);
    ix3m_put_sample(blob, 1, 0, 50);
    ix3m_put_sample(blob, 2, 10, 120);

    libdc_parsed_dive_t result;
    char err[256] = {0};

    int rc = libdc_parse_raw_dive("Ratio", "iX3M 2 GPS Pro", IX3M2_GPS_PRO_MODEL,
                                  blob, size, &result, err, sizeof(err));
    assert(rc == 0);

    assert(!isnan(result.entry_latitude));
    assert(isnan(result.exit_latitude));
    assert(isnan(result.exit_longitude));

    printf("PASS: test_parse_ratio_ix3m_single_fix\n");

    free(result.samples);
    free(result.events);
    free(blob);
}

/* A record with no satellite fix reports 0/0. Treating Null Island as a real
   position would drop the dive in the Gulf of Guinea. */
static void test_parse_ratio_ix3m_null_island_ignored(void) {
    const unsigned int nrecords = 3;
    const unsigned int size = IX3M_HEADER_SIZE + nrecords * IX3M_APOS4_SAMPLE_SIZE;
    unsigned char *blob = (unsigned char *)calloc(1, size);
    assert(blob != NULL);

    put_u16le(blob + 1, nrecords);
    put_u32le(blob + 0x2A, 40000000);

    ix3m_put_info(blob, 0, 0, 0);
    ix3m_put_sample(blob, 1, 0, 50);
    ix3m_put_sample(blob, 2, 10, 120);

    libdc_parsed_dive_t result;
    char err[256] = {0};

    int rc = libdc_parse_raw_dive("Ratio", "iX3M 2 GPS Pro", IX3M2_GPS_PRO_MODEL,
                                  blob, size, &result, err, sizeof(err));
    assert(rc == 0);

    assert(isnan(result.entry_latitude));
    assert(isnan(result.entry_longitude));
    assert(isnan(result.exit_latitude));
    assert(isnan(result.exit_longitude));

    printf("PASS: test_parse_ratio_ix3m_null_island_ignored\n");

    free(result.samples);
    free(result.events);
    free(blob);
}

int main(void) {
    test_null_args();
    test_load_fixture_missing();
    test_unknown_descriptor();
    test_parse_cressi_leonardo();
    test_parse_ratio_ix3m_sample_gps();
    test_parse_ratio_ix3m_single_fix();
    test_parse_ratio_ix3m_null_island_ignored();
    printf("\nAll parse_raw_dive tests passed.\n");
    return 0;
}
