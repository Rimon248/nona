FROM scratch
COPY --chown=65532:65532 control-api /control-api
COPY --chown=65532:65532 admin /admin
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/control-api"]
