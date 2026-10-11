# shellcheck shell=sh
# Fake Marlowe site environment for the e2e image: ubuntu-lmod.Dockerfile
# installs this file as /etc/profile.d/e2e-site.sh. It exports nothing on
# purpose. A Marlowe login shell gets no SCRATCH from the site; the marlowe
# overlay sets PROJECT_ID, PROJECTS and SCRATCH=/scratch/$PROJECT_ID itself
# (marlowe/sh/.config/sh/.profile), so the image only creates
# /scratch/m000191 writable by the user, where that overlay points SCRATCH,
# and Ubuntu's lmod package provides LMOD_DIR through /etc/profile.d/lmod.sh.
# The file exists so the two hpc images are built the same way and so a
# site variable Marlowe turns out to need has one place to go.
