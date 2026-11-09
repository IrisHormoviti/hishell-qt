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
#include <QUrl>

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

QPoint DragHelper::cursorPosition() const
{
	return QCursor::pos();
}

bool DragHelper::mousePressed() const
{
	return QGuiApplication::mouseButtons() & Qt::LeftButton;
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
		performDrag(uris, QPixmap::fromImage(image));
	});
}

void DragHelper::startDragFromGrab(QObject *grab, const QString &uri)
{
	auto *result = qobject_cast<QQuickItemGrabResult *>(grab);
	const QImage image = result ? result->image() : QImage();
	const QStringList uris{uri};
	m_sources = uris;
	QTimer::singleShot(0, this, [this, uris, image] {
		performDrag(uris, QPixmap::fromImage(image));
	});
}

void DragHelper::startDragManyFromGrab(QObject *grab, const QString &uris)
{
	auto *result = qobject_cast<QQuickItemGrabResult *>(grab);
	const QImage image = result ? result->image() : QImage();
	const QStringList list = uris.split('\n', Qt::SkipEmptyParts);
	if (list.isEmpty())
		return;
	m_sources = list;
	QTimer::singleShot(0, this, [this, list, image] {
		performDrag(list, QPixmap::fromImage(image));
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
