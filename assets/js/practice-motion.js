(() => {
  const preference = window.matchMedia('(prefers-reduced-motion: reduce)');
  if (preference.matches || !window.IntersectionObserver || !Element.prototype.animate) return;

  const running = new Map();
  const observer = new IntersectionObserver(entries => {
    entries.forEach(entry => {
      if (!entry.isIntersecting) return;
      const element = entry.target;
      observer.unobserve(element);
      if (preference.matches || element.contains(document.activeElement)) return;
      const animation = element.animate([
        { opacity: 0.65, transform: 'translateY(12px)' },
        { opacity: 1, transform: 'translateY(0)' }
      ], { duration: 420, easing: 'cubic-bezier(.2,.65,.3,1)' });
      running.set(element, animation);
      animation.onfinish = animation.oncancel = () => running.delete(element);
    });
  }, { threshold: 0.08 });

  document.querySelectorAll('.section-intro, .offer-chooser > a, .practice-process, .deliverable, .practice-experience, .practice-closing, .home-recent, .practice-site .post-content > h2').forEach(element => observer.observe(element));

  document.addEventListener('focusin', event => {
    running.forEach((animation, element) => {
      if (element.contains(event.target)) animation.cancel();
    });
  });
  preference.addEventListener('change', event => {
    if (!event.matches) return;
    observer.disconnect();
    running.forEach(animation => animation.cancel());
  });
})();
