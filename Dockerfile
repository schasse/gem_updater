FROM ruby:2.5.0

COPY update_gems.rb /usr/bin/update_gems.rb

RUN wget -O- https://github.com/github/hub/releases/download/v2.2.3/hub-linux-amd64-2.2.3.tgz | tar zx
RUN cp hub-linux-amd64-2.2.3/bin/hub /usr/bin/

RUN echo $GEM_HOME

RUN mkdir -p /mnt
WORKDIR /mnt

CMD /usr/bin/update_gems.rb
