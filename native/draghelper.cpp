#include "draghelper.h"

#include <QCursor>
#include <QDrag>
#include <QGuiApplication>
#include <QImage>
#include <QMimeData>
#include <QPixmap>
#include <QQmlEngine>
#include <QQuickItemGrabResult>
#include <QTimer>
#include <QPainter>
#include <QUrl>

static QPixmap pixmapForDrag(const QImage &image, const QColor &background)
{
	if (image.isNull())
		return {};
	if (!background.isValid())
		return QPixmap::fromImage(image);
	// X11 paints the transparent pixels of a drag pixmap black. Flatten the
	// grab onto the slot background so the drag icon stays readable.
	QImage opaque(image.size(), QImage::Format_ARGB32_Premultiplied);
	opaque.fill(background);
	QPainter painter(&opaque);
	painter.drawImage(0, 0, image);
	painter.end();
	return QPixmap::fromImage(opaque);
}

static QString actionFromModifiers(Qt::KeyboardModifiers modifiers)
{
	if (modifiers & Qt::ShiftModifier)
		return (modifiers & Qt::ControlModifier)
			? QStringLiteral("link") : QStringLiteral("move");
	return QStringLiteral("copy");
}

DragHelper::DragHelper(QObject *parent) : QObject(parent)
{
	m_cursorTimer = new QTimer(this);
	m_cursorTimer->setInterval(20);
	connect(m_cursorTimer, &QTimer::timeout, this, [this] {
		const QPoint position = QCursor::pos();
		emit cursorMoved(position.x(), position.y());
		const QString action =
			actionFromModifiers(QGuiApplication::keyboardModifiers());
		if (action != m_action) {
			m_action = action;
			emit dragActionChanged(action);
		}
	});
}

void DragHelper::setSpringTarget(const QString &path)
{
	for (const QString &source : m_sources) {
		if (QUrl(source).toLocalFile() == path)
			return;
	}
	m_spring = path;
	QTimer::singleShot(700, this, [this] {
		if (!m_spring.isEmpty())
			emit springRequested(m_spring);
	});
}

void DragHelper::clearSpringTarget()
{
	m_spring.clear();
}

bool DragHelper::isSource(const QString &path) const
{
	for (const QString &source : m_sources) {
		if (QUrl(source).toLocalFile() == path)
			return true;
	}
	return false;
}

void DragHelper::startDrag(const QString &uri, const QString &imageUrl)
{
	QImage image;
	if (!imageUrl.isEmpty()) {
		const QUrl url(imageUrl);
		image.load(url.isLocalFile() ? url.toLocalFile() : imageUrl);
	}
	const QStringList uris{uri};
	m_sources = uris;
	QTimer::singleShot(0, this, [this, uris, image] {
		performDrag(uris, pixmapForDrag(image, QColor()));
	});
}

void DragHelper::startDragFromGrab(QObject *grab, const QString &uri,
	const QColor &background)
{
	auto *result = qobject_cast<QQuickItemGrabResult *>(grab);
	const QImage image = result ? result->image() : QImage();
	const QStringList uris{uri};
	m_sources = uris;
	QTimer::singleShot(0, this, [this, uris, image, background] {
		performDrag(uris, pixmapForDrag(image, background));
	});
}

void DragHelper::startDragManyFromGrab(QObject *grab, const QString &uris,
	const QColor &background)
{
	auto *result = qobject_cast<QQuickItemGrabResult *>(grab);
	const QImage image = result ? result->image() : QImage();
	const QStringList list = uris.split('\n', Qt::SkipEmptyParts);
	if (list.isEmpty())
		return;
	m_sources = list;
	QTimer::singleShot(0, this, [this, list, image, background] {
		performDrag(list, pixmapForDrag(image, background));
	});
}

void DragHelper::performDrag(const QStringList &uris, const QPixmap &pixmap)
{
	QDrag drag(this);
	QMimeData *mime = new QMimeData;
	QList<QUrl> urls;
	for (const QString &uri : uris)
		urls.append(QUrl(uri));
	mime->setUrls(urls);
	mime->setText(uris.join('\n'));
	drag.setMimeData(mime);

	if (!pixmap.isNull()) {
		drag.setPixmap(pixmap);
		drag.setHotSpot(pixmap.rect().center());
	}

	m_action = actionFromModifiers(QGuiApplication::keyboardModifiers());
	emit dragActionChanged(m_action);
	m_cursorTimer->start();
	drag.exec(Qt::CopyAction | Qt::MoveAction | Qt::LinkAction);
	m_cursorTimer->stop();
	emit dragFinished();
}

static QObject *dragHelperProvider(QQmlEngine *, QJSEngine *)
{
	return new DragHelper;
}

extern "C" void hishell_register_drag_helper()
{
	qmlRegisterSingletonType<DragHelper>("NativeDrag", 1, 0, "DragHelper",
		dragHelperProvider);
}
