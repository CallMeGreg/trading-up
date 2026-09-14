const page = document.body;
const largeText = document.querySelector('#large-text');
const showTargets = document.querySelector('#show-targets');

largeText.addEventListener('change', () => {
  page.classList.toggle('large-text', largeText.checked);
});

showTargets.addEventListener('change', () => {
  page.classList.toggle('show-targets', showTargets.checked);
});

function showToast(phone, message) {
  const toast = phone.querySelector('.toast');
  if (!toast) return;
  window.clearTimeout(toast.hideTimer);
  toast.textContent = message;
  toast.classList.add('is-visible');
  toast.hideTimer = window.setTimeout(() => toast.classList.remove('is-visible'), 1800);
}

document.querySelectorAll('.more-button').forEach(button => {
  button.addEventListener('click', event => {
    event.stopPropagation();
    const menu = button.nextElementSibling;
    const willOpen = !menu.classList.contains('is-open');

    document.querySelectorAll('.more-menu.is-open').forEach(openMenu => {
      openMenu.classList.remove('is-open');
      openMenu.previousElementSibling.setAttribute('aria-expanded', 'false');
    });

    menu.classList.toggle('is-open', willOpen);
    button.setAttribute('aria-expanded', String(willOpen));
  });
});

document.addEventListener('click', () => {
  document.querySelectorAll('.more-menu.is-open').forEach(menu => {
    menu.classList.remove('is-open');
    menu.previousElementSibling.setAttribute('aria-expanded', 'false');
  });
});

document.querySelectorAll('.select-copy').forEach(row => {
  row.addEventListener('click', () => {
    const phone = row.closest('.phone');
    phone.querySelectorAll('.select-copy').forEach(other => {
      const selected = other === row;
      other.classList.toggle('is-selected', selected);
      other.setAttribute('aria-pressed', String(selected));
      other.querySelector('.radio-mark').textContent = selected ? '✓' : '';
    });
    phone.querySelector('.selected-copy-number').textContent = row.dataset.copy;
    showToast(phone, `Copy ${row.dataset.copy} selected`);
  });
});

document.querySelectorAll('.mode-button').forEach(button => {
  button.addEventListener('click', () => {
    const phone = button.closest('.mode-phone');
    const mode = button.dataset.mode;
    const selling = mode === 'sell';

    phone.classList.toggle('grade-mode', !selling);
    phone.classList.toggle('sell-mode', selling);
    phone.querySelectorAll('.mode-button').forEach(other => {
      const active = other === button;
      other.classList.toggle('is-active', active);
      other.setAttribute('aria-pressed', String(active));
    });

    phone.querySelectorAll('.mode-action').forEach(action => {
      action.classList.toggle('grade-button', !selling);
      action.classList.toggle('sell-button', selling);
      action.dataset.action = selling ? 'sell' : 'grade';
      action.innerHTML = selling
        ? '<span class="money-dot">$</span>Sell $0.68'
        : '<span class="seal-icon">✹</span>Grade $4.00';
    });

    showToast(phone, selling ? 'Sell actions shown' : 'Grade actions shown');
  });
});

document.querySelectorAll('[data-action]').forEach(button => {
  button.addEventListener('click', event => {
    event.stopPropagation();
    const phone = button.closest('.phone');
    const action = button.dataset.action;
    showToast(
      phone,
      action === 'sell'
        ? 'Sell confirmation would open next'
        : 'Grade reveal would start now'
    );
  });
});
