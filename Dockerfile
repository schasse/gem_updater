FROM ubuntu:disco-20190718
ENV LANG=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    hub \
    wget \
    ca-certificates \
    build-essential \
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    libxml2 libxml2-dev libxslt1-dev \
    libmysqlclient-dev mysql-client \
 && rm -rf /var/lib/apt/lists/*

# install rbenv and ruby build
ENV RBENV_V=v1.1.2
ENV RUBY_BUILD_V=v20190615

RUN git clone --branch $RBENV_V --depth 1 https://github.com/rbenv/rbenv.git $HOME/.rbenv \
 && cd $HOME/.rbenv && src/configure && make -C src \
 && echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> $HOME/.bash_profile \
 && echo 'eval "$(rbenv init -)"' >> $HOME/.bash_profile

RUN mkdir -p $HOME/.rbenv/plugins \
 && git clone --branch $RUBY_BUILD_V --depth 1 https://github.com/rbenv/ruby-build.git $HOME/.rbenv/plugins/ruby-build

RUN bash -lc 'rbenv install 2.5.1'
RUN bash -lc 'rbenv global 2.5.1 && gem install bundler --version 1.16.2 && gem install rspec --version 3.8.0'

COPY . /usr/lib/gem_updater
RUN ln -s /usr/lib/gem_updater/update_gems.rb /usr/bin/update_gems.rb

RUN mkdir -p /mnt
WORKDIR /mnt

CMD ["/bin/bash", "-lc", "/usr/bin/update_gems.rb"]
